@_spi(Runners) import SwiftTUIRuntime
import SwiftTUIWASISurfaceBridge
import Synchronization

package protocol WebHostByteSource: Sendable {
  /// Inbound client bytes, tagged with the connection that produced them.
  func inboundEvents() -> AsyncStream<WebHostInboundEvent>
  /// The connection whose bytes may still be parsed and applied.
  func currentConnectionToken() async -> UInt64?
  func inputLease(for token: UInt64) async -> InputConnectionLease?
  func recordDiscardedInboundChunk(_ chunk: WebHostDiscardedInboundChunk) async
}

/// Deterministic observation and barrier points for the reader's connection
/// isolation. Internal, `nil` by default in production, and reachable only by
/// constructing a reader directly — no parser or transport protocol grows a
/// testing requirement.
package struct WebSocketInputReaderTestHooks: Sendable {
  package enum ParsedRecordKind: Sendable {
    case caps
    case terminalInput
  }

  /// Reports the reader's actual parser ownership after every change.
  package var parserStateDidChange: (@Sendable (UInt64?, Int) -> Void)?
  /// Holds a parsed record immediately before its application-time token
  /// check, so a test can retire that connection in the gap.
  package var beforeApplyParsedRecord: (@Sendable (UInt64, ParsedRecordKind) async -> Void)?

  package init(
    parserStateDidChange: (@Sendable (UInt64?, Int) -> Void)? = nil,
    beforeApplyParsedRecord: (@Sendable (UInt64, ParsedRecordKind) async -> Void)? = nil
  ) {
    self.parserStateDidChange = parserStateDidChange
    self.beforeApplyParsedRecord = beforeApplyParsedRecord
  }
}

package struct WebSocketInputReaderLifecycle: Sendable {
  package var connectionOpened: @Sendable (UInt64) -> Void
  package var connectionClosed: @Sendable (UInt64) -> Void = { _ in }
  package var inputAllowed: @Sendable () -> Bool = { true }
}

/// Reads client bytes into scene input, owning parser state for exactly one
/// connection at a time.
///
/// Three refusals make a reconnect safe, and each is separately observable:
///
/// - **Before parsing.** A queued chunk whose connection is no longer current
///   is discarded rather than fed to the parser, so a chunk that was still in
///   flight when its client was replaced can never combine with the new
///   client's bytes.
/// - **At a connection boundary.** Opening a connection resets parser
///   fragments; a partial record left by the previous connection is discarded,
///   not completed by the successor's first chunk.
/// - **Before applying.** The token is checked again immediately before a
///   parsed capability declaration is applied or a parsed input event is
///   yielded, because the connection can retire while a record is in hand.
package final class WebSocketInputReader: ScopedInputReading, Sendable {
  private struct ReaderState {
    var parser = WebSurfaceInputParser()
    /// The connection whose partial record the parser holds.
    var parserToken: UInt64?
    /// The most recently opened connection in the replayed event stream. This
    /// is what separates "was current when it arrived" from "was already
    /// superseded when it arrived" for a chunk that is stale by now.
    var streamToken: UInt64?
  }

  private let source: any WebHostByteSource
  private let controlHandler: @Sendable (WebSurfaceInputControlMessage, UInt64) async -> Void
  private let connectionOpened: @Sendable (UInt64) -> Void
  private let connectionClosed: @Sendable (UInt64) -> Void
  private let inputAllowed: @Sendable () -> Bool
  private let hooks: WebSocketInputReaderTestHooks?
  private let state = Mutex(ReaderState())

  /// Internal because `WebSurfaceInputControlMessage` reaches this module
  /// through an internal import; the package-visible entry point is the
  /// `channel:transport:` convenience initializer below.
  init(
    source: any WebHostByteSource,
    hooks: WebSocketInputReaderTestHooks? = nil,
    lifecycle: WebSocketInputReaderLifecycle? = nil,
    controlHandler: @escaping @Sendable (WebSurfaceInputControlMessage, UInt64) async -> Void = {
      _, _ in
    }
  ) {
    self.source = source
    if let lifecycle {
      self.inputAllowed = lifecycle.inputAllowed
      self.connectionClosed = lifecycle.connectionClosed
      self.connectionOpened = lifecycle.connectionOpened
    } else {
      self.inputAllowed = { true }
      self.connectionClosed = { (_: UInt64) in }
      self.connectionOpened = { (_: UInt64) in }
    }
    self.hooks = hooks
    self.controlHandler = controlHandler
  }

  /// The production wiring: control records reach the transport, and a
  /// capability declaration is applied through the channel so the re-anchor,
  /// the activation, and the automatic refresh happen in one atomic step
  /// against the connection that sent it.
  package convenience init(
    channel: WebHostSceneChannel,
    transport: WebSocketSurfaceTransport,
    signalReader: InProcessSignalReader? = nil,
    hooks: WebSocketInputReaderTestHooks? = nil,
    sharedViewportRequired: Bool = false
  ) {
    self.init(
      source: channel, hooks: hooks,
      lifecycle: .init(
        connectionOpened: {
          transport.beginGeometrySession($0)
          if sharedViewportRequired { signalReader?.send("SIGWINCH") }
        },
        connectionClosed: {
          transport.endGeometrySession($0)
          if sharedViewportRequired { signalReader?.send("SIGWINCH") }
        },
        inputAllowed: {
          !sharedViewportRequired
            || (transport.isConnected && transport.wireCapabilities.sharedViewport)
        })
    ) { message, token in
      switch message {
      case .geometry(let request):
        if transport.updateGeometry(request, connectionToken: token) {
          signalReader?.send("SIGWINCH")
        }
      case .resize(let size, let cellPixelSize):
        transport.updateSurfaceSize(size, cellPixelSize: cellPixelSize)
        signalReader?.send("SIGWINCH")
      case .style(let style):
        transport.updateStyle(style)
        signalReader?.send("SIGWINCH")
      case .pointerCapabilities(let supportsScrollPanning):
        transport.updatePointerCapabilities(
          supportsScrollPanning: supportsScrollPanning
        )
        signalReader?.send("SIGWINCH")
      case .capabilities(let capabilities):
        guard
          !sharedViewportRequired
            || (capabilities.geometryRevisions && capabilities.sharedViewport)
        else {
          let issue = RuntimeIssue(
            severity: .error, code: "companion-client-outdated",
            message:
              "This shared terminal session requires its matching browser assets. Reload the companion URL with the browser cache cleared."
          )
          try? await channel.send(
            Array(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue).utf8), connectionToken: token)
          return
        }
        await channel.applyCapabilities(
          token: token,
          reanchor: { transport.declareCapabilities(capabilities, connectionToken: token) },
          requestRefresh: {
            transport.requestSurfaceRefresh()
            if sharedViewportRequired { signalReader?.send("SIGWINCH") }
          }
        )
      case .resync(let request):
        transport.requestResync(request)
      }
    }
  }

  package func inputEvents() -> AsyncStream<InputEvent> {
    AsyncStream { continuation in
      let task = Task {
        for await event in self.source.inboundEvents() {
          await self.process(event, yielding: continuation)
          await Task.yield()
        }
        continuation.finish()
      }

      continuation.onTermination = { _ in
        task.cancel()
      }
    }
  }

  package func scopedInputEvents() -> AsyncStream<ScopedInputEvent> {
    AsyncStream { continuation in
      let task = Task {
        for await event in self.source.inboundEvents() {
          await self.processScoped(
            event, yielding: { continuation.yield($0) },
            finish: { continuation.finish() })
          await Task.yield()
        }
        continuation.finish()
      }
      continuation.onTermination = { _ in task.cancel() }
    }
  }

  /// One reader step. The production stream loop and every deterministic
  /// harness go through here, so no test exercises a private copy of it.
  package func process(
    _ event: WebHostInboundEvent,
    yielding continuation: AsyncStream<InputEvent>.Continuation
  ) async {
    await processScoped(
      event, yielding: { continuation.yield($0.event) },
      finish: { continuation.finish() })
  }

  private func processScoped(
    _ event: WebHostInboundEvent,
    yielding yield: @escaping @Sendable (ScopedInputEvent) -> Void,
    finish: @Sendable () -> Void
  ) async {
    switch event {
    case .shutdown:
      finish()
    case .connectionOpened(let token):
      await openConnection(token: token)
    case .connectionClosed(let token):
      connectionClosed(token)
    case .bytes(let token, let bytes):
      await processBytes(token: token, bytes: bytes, yielding: yield)
    }
  }

  private func openConnection(
    token: UInt64
  ) async {
    connectionOpened(token)
    let abandoned = state.withLock { state -> (token: UInt64, bytes: [UInt8])? in
      let leftover = state.parser.bufferedCommandBytes
      let previousToken = state.parserToken
      state.parser = WebSurfaceInputParser(session: token)
      state.parserToken = token
      state.streamToken = token
      guard !leftover.isEmpty, let previousToken, previousToken != token else {
        return nil
      }
      return (previousToken, leftover)
    }
    if let abandoned {
      await source.recordDiscardedInboundChunk(
        .init(token: abandoned.token, bytes: abandoned.bytes, reason: .connectionBoundary))
    }
    hooks?.parserStateDidChange?(token, 0)
  }

  private func processBytes(
    token: UInt64,
    bytes: [UInt8],
    yielding yield: @escaping @Sendable (ScopedInputEvent) -> Void
  ) async {
    guard await source.currentConnectionToken() == token else {
      let wasCurrentOnArrival = state.withLock(\.streamToken) == token
      await source.recordDiscardedInboundChunk(
        .init(
          token: token,
          bytes: bytes,
          reason: wasCurrentOnArrival ? .staleAtConsumption : .staleAtIngress
        ))
      return
    }

    let parsed = state.withLock { state in
      state.parserToken = token
      return state.parser.feedRecords(bytes)
    }
    hooks?.parserStateDidChange?(token, state.withLock(\.parser.bufferedCommandBytes).count)

    for record in parsed {
      switch record {
      case .control(let message):
        if case .capabilities = message {
          await hooks?.beforeApplyParsedRecord?(token, .caps)
        }
        guard await source.currentConnectionToken() == token else { continue }
        await controlHandler(message, token)
      case .input(let event):
        await hooks?.beforeApplyParsedRecord?(token, .terminalInput)
        guard await source.currentConnectionToken() == token else { continue }
        var scopedEvent = event
        if case .accessibility(var request) = scopedEvent {
          request.hostSession = token
          scopedEvent = .accessibility(request)
        }
        guard inputAllowed(), let lease = await source.inputLease(for: token) else { continue }
        yield(ScopedInputEvent(scopedEvent, origin: .browser, lease: lease))
      }
    }
  }
}
