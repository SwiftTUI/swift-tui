@_spi(Runners) import SwiftTUIRuntime
import SwiftTUIWASISurfaceBridge
import Synchronization

package protocol WebHostByteSink: Sendable {
  func send(_ bytes: [UInt8]) async throws
}

package enum WebHostByteSinkError: Error, Equatable, Sendable, CustomStringConvertible {
  case sendFailed(String)
  case sendDidNotComplete
  case sendTimedOut

  package var description: String {
    switch self {
    case .sendFailed(let message):
      return "WebHost byte sink failed: \(message)"
    case .sendDidNotComplete:
      return "WebHost byte sink did not complete."
    case .sendTimedOut:
      return "WebHost byte sink timed out."
    }
  }
}

package final class WebSocketSurfaceTransport: PresentationSurfaceMetricsProvider,
  RasterPresentationSurface,
  ClipboardWritingPresentationSurface,
  SemanticHostFramePresentationSurface, Sendable
{
  private struct State: Sendable {
    var surfaceSize: CellSize
    var renderStyle: TerminalRenderStyle
    var graphicsCapabilities: TerminalGraphicsCapabilities
    var pointerInputCapabilities: PointerInputCapabilities
    var transmittedImageIDs: Set<String>
  }

  private let state: Mutex<State>
  private let pump: ByteSinkPump

  package let capabilityProfile = TerminalCapabilityProfile(
    glyphLevel: .unicode,
    colorLevel: .trueColor,
    emitsStyleEscapeSequences: false,
    supportsHyperlinks: true,
    supportsMouseReporting: true,
    supportsSynchronizedOutput: false
  )

  package init(
    surfaceSize: CellSize,
    sink: any WebHostByteSink,
    renderStyle: TerminalRenderStyle = .init(appearance: .fallback),
    sendTimeoutNanoseconds: UInt64 = 10_000_000_000
  ) {
    self.pump = ByteSinkPump(sink: sink, sendTimeoutNanoseconds: sendTimeoutNanoseconds)
    state = Mutex(
      State(
        surfaceSize: surfaceSize,
        renderStyle: renderStyle,
        graphicsCapabilities: .none,
        pointerInputCapabilities: .cellOnly,
        transmittedImageIDs: []
      )
    )
  }

  package var surfaceSize: CellSize {
    state.withLock(\.surfaceSize)
  }

  package var appearance: TerminalAppearance {
    state.withLock(\.renderStyle.appearance)
  }

  package var theme: Theme? {
    state.withLock(\.renderStyle.theme)
  }

  package var graphicsCapabilities: TerminalGraphicsCapabilities {
    state.withLock(\.graphicsCapabilities)
  }

  package var pointerInputCapabilities: PointerInputCapabilities {
    state.withLock(\.pointerInputCapabilities)
  }

  package func updateSurfaceSize(
    _ surfaceSize: CellSize,
    cellPixelSize: PixelSize? = nil
  ) {
    state.withLock { state in
      state.surfaceSize = surfaceSize
      state.graphicsCapabilities.cellPixelSize = cellPixelSize
      state.pointerInputCapabilities = Self.pointerInputCapabilities(for: cellPixelSize)
    }
  }

  package func updateStyle(
    _ style: TerminalRenderStyle
  ) {
    state.withLock { state in
      state.renderStyle = style
    }
  }

  @discardableResult
  @MainActor
  package func writeClipboard(_ text: String) throws -> Bool {
    try sendBytes(Array(WebSurfaceFrameEncoder.encodeClipboard(text).utf8))
    return true
  }

  package func notifyRuntimeIssue(_ issue: RuntimeIssue) throws {
    try sendBytes(Array(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue).utf8))
  }

  @discardableResult
  package func present(
    _ surface: RasterSurface
  ) throws -> TerminalPresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          surface,
          damage: nil,
          fallbackBackground: state.renderStyle.appearance.backgroundColor,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try sendBytes(bytes)
    return .rasterHostMetrics(
      for: surface,
      damage: nil,
      bytesWritten: bytes.count
    )
  }

  @discardableResult
  package func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    let bytes = state.withLock { state in
      Array(
        WebSurfaceFrameEncoder.encode(
          frame,
          fallbackBackground: state.renderStyle.appearance.backgroundColor,
          knownImageIDs: &state.transmittedImageIDs
        ).utf8
      )
    }
    try sendBytes(bytes)
    return .rasterHostMetrics(
      for: frame.raster,
      damage: frame.rasterDamage,
      bytesWritten: bytes.count
    )
  }

  /// Suspends until every byte batch handed to the transport has been sent.
  ///
  /// Throws the first send failure observed, if any. This is the awaitable
  /// completion signal callers use instead of blocking inside `present`.
  package func drain() async throws {
    await pump.waitUntilIdle()
    if let error = pump.currentError() {
      throw error
    }
  }

  private static func pointerInputCapabilities(
    for cellPixelSize: PixelSize?
  ) -> PointerInputCapabilities {
    guard let cellPixelSize else {
      return .cellOnly
    }
    return PointerInputCapabilities(
      precision: .subCell(
        source: .webPixels,
        metrics: CellPixelMetrics(
          width: cellPixelSize.width,
          height: cellPixelSize.height,
          source: .reported
        )
      ),
      supportsHover: true
    )
  }

  private func sendBytes(
    _ bytes: [UInt8]
  ) throws {
    guard !bytes.isEmpty else {
      return
    }
    // Surface a prior send failure synchronously so a stuck transport stops
    // accepting frames, then hand the batch off without blocking. The actual
    // send happens on the pump's drain task; callers await `drain()` to learn
    // when it finished.
    if let error = pump.currentError() {
      throw error
    }
    pump.enqueue(bytes)
  }
}

/// Buffers byte batches and drains them to the sink on a dedicated task.
///
/// `enqueue` is synchronous, ordered, and never blocks the caller. It replaces
/// a `DispatchSemaphore` bridge that blocked a cooperative-pool thread while a
/// child task did the async send — a pattern that deadlocked the pool under
/// parallel load and surfaced as spurious "byte sink timed out" failures.
///
/// Send failures are observed either on a later `enqueue` (via `currentError`)
/// or by awaiting `waitUntilIdle()`. The per-send timeout still applies, but it
/// races *inside* the drain task and so never blocks a presenting caller.
private final class ByteSinkPump: Sendable {
  private enum DrainStep {
    case batch([UInt8])
    case finished([CheckedContinuation<Void, Never>])
  }

  private struct State {
    var pending: [[UInt8]] = []
    var isDraining = false
    var firstError: WebHostByteSinkError?
    var idleWaiters: [CheckedContinuation<Void, Never>] = []
  }

  private let sink: any WebHostByteSink
  private let sendTimeoutNanoseconds: UInt64
  private let state = Mutex(State())

  init(sink: any WebHostByteSink, sendTimeoutNanoseconds: UInt64) {
    self.sink = sink
    self.sendTimeoutNanoseconds = sendTimeoutNanoseconds
  }

  /// The first send failure observed so far, if any.
  func currentError() -> WebHostByteSinkError? {
    state.withLock(\.firstError)
  }

  /// Appends `bytes` to the FIFO send queue, starting a drain task if idle.
  func enqueue(_ bytes: [UInt8]) {
    let shouldStartDrain = state.withLock { state -> Bool in
      state.pending.append(bytes)
      guard !state.isDraining else { return false }
      state.isDraining = true
      return true
    }
    if shouldStartDrain {
      Task { await self.drain() }
    }
  }

  /// Suspends until the send queue is fully drained.
  func waitUntilIdle() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let isIdle = state.withLock { state -> Bool in
        if !state.isDraining, state.pending.isEmpty {
          return true
        }
        state.idleWaiters.append(continuation)
        return false
      }
      if isIdle {
        continuation.resume()
      }
    }
  }

  private func drain() async {
    while true {
      let step = state.withLock { state -> DrainStep in
        guard !state.pending.isEmpty else {
          state.isDraining = false
          defer { state.idleWaiters = [] }
          return .finished(state.idleWaiters)
        }
        return .batch(state.pending.removeFirst())
      }

      switch step {
      case .batch(let batch):
        if currentError() == nil {
          do {
            try await sendWithTimeout(batch)
          } catch let error as WebHostByteSinkError {
            recordError(error)
          } catch {
            recordError(.sendFailed(String(describing: error)))
          }
        }
      case .finished(let waiters):
        for waiter in waiters {
          waiter.resume()
        }
        return
      }
    }
  }

  private func recordError(_ error: WebHostByteSinkError) {
    state.withLock { state in
      if state.firstError == nil {
        state.firstError = error
      }
    }
  }

  private func sendWithTimeout(_ bytes: [UInt8]) async throws {
    let sink = self.sink
    let timeoutNanoseconds = sendTimeoutNanoseconds
    try await withThrowingTaskGroup(of: Void.self) { group in
      group.addTask {
        try await sink.send(bytes)
      }
      group.addTask {
        try await Task.sleep(nanoseconds: timeoutNanoseconds)
        throw WebHostByteSinkError.sendTimedOut
      }
      defer { group.cancelAll() }
      try await group.next()
    }
  }
}
