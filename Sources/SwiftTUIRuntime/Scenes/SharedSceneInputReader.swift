import SwiftTUICore

/// Combines input at the scene owner. Browser departure never finishes the
/// scene; secondary terminal readers can restart without restarting its graph.
@MainActor
package final class SharedSceneInputReader: @preconcurrency ScopedInputReading,
  @preconcurrency TerminalInputCapabilityConfiguring, TerminalInputHandoffSuspending
{
  private let terminal: any TerminalInputReading
  private nonisolated let handoff: (any TerminalInputHandoffSuspending)?
  private let terminalEndsSession: Bool
  private let stream: AsyncStream<ScopedInputEvent>
  private let continuation: AsyncStream<ScopedInputEvent>.Continuation
  private var terminalTask: Task<Void, Never>?
  private var browserTask: Task<Void, Never>?
  private var terminalLease: InputConnectionLease?
  private var terminalWanted: Bool
  private var started = false
  private var finished = false
  private var browser: (any ScopedInputReading)?
  package var terminalEnded: (@MainActor () -> Void)?

  package init(terminal: any TerminalInputReading, attached: Bool, endsSession: Bool) {
    self.terminal = terminal
    self.handoff = terminal as? any TerminalInputHandoffSuspending
    terminalEndsSession = endsSession
    terminalWanted = attached
    (stream, continuation) = AsyncStream.makeStream()
  }

  package func attachBrowser(_ reader: any ScopedInputReading) {
    precondition(browser == nil, "One browser ingress owns the scene connection channel")
    browser = reader
    if started { startBrowserInput() }
  }

  package func scopedInputEvents() -> AsyncStream<ScopedInputEvent> {
    if !started {
      started = true
      if terminalWanted { startTerminalInput() }
      startBrowserInput()
      continuation.onTermination = { [weak self] _ in
        Task { @MainActor in self?.finish() }
      }
    }
    return stream
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    let events = scopedInputEvents()
    return AsyncStream { continuation in
      let task = Task { @MainActor in
        for await event in events { continuation.yield(event.event) }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  package func setTerminalAttached(_ attached: Bool) {
    terminalWanted = attached
    if attached {
      if started { startTerminalInput() }
    } else {
      terminalLease?.retire()
      terminalLease = nil
      terminalTask?.cancel()
      terminalTask = nil
    }
  }

  private func startTerminalInput() {
    guard !finished, terminalTask == nil else { return }
    let events = terminal.inputEvents()
    let lease = InputConnectionLease()
    terminalLease = lease
    terminalTask = Task { @MainActor [weak self] in
      for await event in events {
        guard !Task.isCancelled, let self else { return }
        continuation.yield(.init(event, origin: .terminal, lease: lease))
      }
      guard !Task.isCancelled, let self, terminalLease === lease else { return }
      terminalTask = nil
      if terminalEndsSession {
        // Retain the final input burst before EOF, just as the ordinary reader does.
        finish(retireTerminalInput: false)
      } else {
        lease.retire()
        terminalWanted = false
        terminalEnded?()
      }
    }
  }

  private func startBrowserInput() {
    guard !finished, browserTask == nil, let browser else { return }
    let events = browser.scopedInputEvents()
    browserTask = Task { @MainActor [weak self] in
      for await event in events {
        guard !Task.isCancelled, let self else { return }
        continuation.yield(event)
      }
    }
  }

  package func finish(retireTerminalInput: Bool = true) {
    guard !finished else { return }
    finished = true
    if retireTerminalInput { terminalLease?.retire() }
    terminalTask?.cancel()
    browserTask?.cancel()
    terminalTask = nil
    browserTask = nil
    continuation.finish()
  }

  package func updateInputCapabilities(_ capabilities: ResolvedTerminalInputCapabilities) {
    (terminal as? any TerminalInputCapabilityConfiguring)?.updateInputCapabilities(capabilities)
  }

  package nonisolated func withInputSuspended<T>(_ body: () throws -> T) rethrows -> T {
    if let handoff { return try handoff.withInputSuspended(body) }
    return try body()
  }

  package func withInputSuspended<T: Sendable>(
    _ body: @MainActor @Sendable () async throws -> T
  ) async rethrows -> T {
    if let handoff { return try await handoff.withInputSuspended(body) }
    return try await body()
  }
}
