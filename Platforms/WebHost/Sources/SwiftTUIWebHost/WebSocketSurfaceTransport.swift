// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  @_spi(Runners) import SwiftTUIRuntime
  import SwiftTUIWASISurfaceBridge
  import Synchronization

  package protocol WebHostByteSink: Sendable {
    func send(_ bytes: [UInt8]) async throws
    func send(_ bytes: [UInt8], connectionToken: UInt64?) async throws
    func disconnect(connectionToken: UInt64?) async
  }

  extension WebHostByteSink {
    package func send(_ bytes: [UInt8], connectionToken: UInt64?) async throws {
      try await send(bytes)
    }

    package func disconnect(connectionToken: UInt64?) async {}
  }

  package enum WebHostByteSinkError: Error, Equatable, Sendable, CustomStringConvertible {
    case sendFailed(String)
    case sendDidNotComplete
    case sendTimedOut
    case outboundBacklogExceeded

    package var description: String {
      switch self {
      case .sendFailed(let message):
        return "WebHost byte sink failed: \(message)"
      case .sendDidNotComplete:
        return "WebHost byte sink did not complete."
      case .sendTimedOut:
        return "WebHost byte sink timed out."
      case .outboundBacklogExceeded:
        return "WebHost outbound backlog exceeded 32 records or 4 MiB; reconnect required."
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
      var encodingState: HostWireEncodingState
      var wireCapabilities: HostWireCapabilities
      var connectionToken: UInt64?
      var encodingGeneration: UInt64 = 0
      /// The most recent frame presented to this transport, retained so a
      /// reconnecting client can be given a keyframe without waiting for the app
      /// to produce one. An idle app produces none, and the pre-capabilities
      /// session deliberately drops everything sent before the declaration, so
      /// without this the reconnecting client would stay blank.
      var lastPresentedFrame: RetainedFrame?
      /// The client's last `pointer:panning=` declaration, kept apart from
      /// `pointerInputCapabilities` so a resize (which recomputes precision from
      /// fresh cell metrics) cannot discard it.
      var supportsScrollPanning = false
    }

    private enum RetainedFrame: Sendable {
      case raster(RasterSurface)
      case semantic(SemanticHostFrame)
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
          encodingState: HostWireCapabilities().negotiatedEncodingState(),
          wireCapabilities: HostWireCapabilities(),
          lastPresentedFrame: nil
        )
      )
    }

    /// The client's declared wire capabilities (`caps:` control record;
    /// absence keeps the defaults — today's bytes).
    package var wireCapabilities: HostWireCapabilities {
      state.withLock(\.wireCapabilities)
    }

    /// Declaring capabilities marks a fresh client connection: the browser
    /// client sends `caps:` exactly once, first, per socket, so its arrival
    /// re-anchors the cross-connection encoding state — the next frame is a
    /// full keyframe with image payloads re-transmitted (the F55 reload
    /// defect), and delta emission is negotiated from the declaration (a
    /// client that declares delta acceptance receives v3 `deltaRows` records
    /// for steady frames; undeclared clients keep today's full frames, byte
    /// for byte).
    ///
    /// Ingress lifecycle: once per connection, before any surface record is
    /// deliverable. `WebHostSceneChannel.applyCapabilities` owns the gate — it
    /// accepts a declaration only from the current connection while that
    /// connection is still pre-capabilities, then re-anchors here, marks the
    /// session surface-active, and requests a refresh. A second declaration on
    /// the same connection is not a new epoch.
    package func declareCapabilities(
      _ capabilities: HostWireCapabilities,
      connectionToken: UInt64? = nil
    ) {
      state.withLock { state in
        state.wireCapabilities = capabilities
        state.encodingState = capabilities.negotiatedEncodingState()
        state.connectionToken = connectionToken
        pump.beginConnection(connectionToken: connectionToken)
        state.encodingGeneration = pump.generation
      }
    }

    package func requestResync(
      _ request: HostWireResyncRequest
    ) {
      state.withLock { state in
        state.encodingState.requestResync(request)
      }
    }

    /// Re-encodes and sends the most recently presented frame, if there is one.
    ///
    /// Called by the channel immediately after a capability declaration
    /// re-anchors the encoding state, so the record produced here is a full
    /// keyframe in the new epoch — the first surface record the reconnecting
    /// client is allowed to receive. A no-op before the first present.
    package func requestSurfaceRefresh() {
      state.withLock { state in
        guard let retained = state.lastPresentedFrame else {
          return
        }
        guard prepareEncoding(&state) else { return }
        let background = state.renderStyle.appearance.backgroundColor
        let bytes: [UInt8]
        switch retained {
        case .raster(let surface):
          bytes = Array(
            WebSurfaceFrameEncoder.encode(
              surface,
              damage: nil,
              fallbackBackground: background,
              state: &state.encodingState
            ).utf8)
        case .semantic(let frame):
          bytes = Array(
            WebSurfaceFrameEncoder.encode(
              frame,
              fallbackBackground: background,
              state: &state.encodingState
            ).utf8)
        }
        pump.enqueue(
          bytes, connectionToken: state.connectionToken, generation: state.encodingGeneration,
          isSurface: true)
      }
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
        state.pointerInputCapabilities = Self.pointerInputCapabilities(
          for: cellPixelSize,
          supportsScrollPanning: state.supportsScrollPanning
        )
      }
    }

    /// Applies the client's `pointer:` paradigm declaration.
    ///
    /// Held apart from the wire capabilities on purpose: `caps:` describes what
    /// the *decoder* accepts and is a once-per-connection epoch marker, whereas
    /// this describes what the *device* is and may be re-declared at any time
    /// (a tablet docked to a mouse). See
    /// ``PointerInputCapabilities/supportsScrollPanning``.
    package func updatePointerCapabilities(
      supportsScrollPanning: Bool
    ) {
      state.withLock { state in
        state.supportsScrollPanning = supportsScrollPanning
        state.pointerInputCapabilities = Self.pointerInputCapabilities(
          for: state.graphicsCapabilities.cellPixelSize,
          supportsScrollPanning: supportsScrollPanning
        )
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
      sendBytes(Array(WebSurfaceFrameEncoder.encodeClipboard(text).utf8))
    }

    package func notifyRuntimeIssue(_ issue: RuntimeIssue) throws {
      if !sendBytes(Array(WebSurfaceFrameEncoder.encodeRuntimeIssue(issue).utf8)) {
        throw WebHostByteSinkError.outboundBacklogExceeded
      }
    }

    @discardableResult
    package func present(
      _ surface: RasterSurface
    ) throws -> TerminalPresentationMetrics {
      let bytes = state.withLock { state -> [UInt8] in
        state.lastPresentedFrame = .raster(surface)
        guard prepareEncoding(&state) else { return [] }
        let bytes = Array(
          WebSurfaceFrameEncoder.encode(
            surface,
            damage: nil,
            fallbackBackground: state.renderStyle.appearance.backgroundColor,
            state: &state.encodingState
          ).utf8
        )
        return pump.enqueue(
          bytes, connectionToken: state.connectionToken, generation: state.encodingGeneration,
          isSurface: true)
          ? bytes : []
      }
      return .rasterHostMetrics(
        for: surface,
        damage: nil,
        bytesWritten: bytes.count
      )
    }

    @discardableResult
    package func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
      let bytes = state.withLock { state -> [UInt8] in
        state.lastPresentedFrame = .semantic(frame)
        guard prepareEncoding(&state) else { return [] }
        let bytes = Array(
          WebSurfaceFrameEncoder.encode(
            frame,
            fallbackBackground: state.renderStyle.appearance.backgroundColor,
            state: &state.encodingState
          ).utf8
        )
        return pump.enqueue(
          bytes, connectionToken: state.connectionToken, generation: state.encodingGeneration,
          isSurface: true)
          ? bytes : []
      }
      return .rasterHostMetrics(
        for: frame.raster,
        damage: frame.rasterDamage,
        bytesWritten: bytes.count
      )
    }

    /// Suspends until every byte batch handed to the transport has been sent.
    ///
    /// Throws the most recent send failure not yet cleared by a successful
    /// send, if any. This is the awaitable completion signal callers use
    /// instead of blocking inside `present`.
    package func drain() async throws {
      await pump.waitUntilIdle()
      if let error = pump.currentError() {
        throw error
      }
    }

    package var outboundBacklog: WebHostOutboundBudget { pump.backlog }

    private static func pointerInputCapabilities(
      for cellPixelSize: PixelSize?,
      supportsScrollPanning: Bool
    ) -> PointerInputCapabilities {
      guard let cellPixelSize else {
        return PointerInputCapabilities(supportsScrollPanning: supportsScrollPanning)
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
        supportsHover: true,
        supportsScrollPanning: supportsScrollPanning
      )
    }

    private func prepareEncoding(_ state: inout State) -> Bool {
      guard pump.canEnqueue(connectionToken: state.connectionToken) else { return false }
      let generation = pump.generation
      if state.encodingGeneration != generation {
        state.encodingState = state.wireCapabilities.negotiatedEncodingState()
        state.encodingGeneration = generation
      }
      return true
    }

    private func sendBytes(
      _ bytes: [UInt8]
    ) -> Bool {
      state.withLock { state in
        pump.enqueue(bytes, connectionToken: state.connectionToken)
      }
    }
  }

  /// A bounded FIFO. Capacity includes the active send. Overflow closes the
  /// connection and refuses publication until a new capability declaration;
  /// it never splices a newer delta into a stream with missing records.
  private final class ByteSinkPump: Sendable {
    private struct Batch {
      var bytes: [UInt8]
      var connectionToken: UInt64?
      var generation: UInt64
      var isSurface: Bool
    }

    private enum DrainStep {
      case batch(Batch)
      case finished([CheckedContinuation<Void, Never>])
    }

    private struct State {
      var pending: [Batch] = []
      var budget = WebHostOutboundBudget()
      var generation: UInt64 = 0
      var overflowed = false
      var isDraining = false
      var lastError: WebHostByteSinkError?
      var idleWaiters: [CheckedContinuation<Void, Never>] = []
    }

    private let sink: any WebHostByteSink
    private let sendTimeoutNanoseconds: UInt64
    private let state = Mutex(State())

    init(sink: any WebHostByteSink, sendTimeoutNanoseconds: UInt64) {
      self.sink = sink
      self.sendTimeoutNanoseconds = sendTimeoutNanoseconds
    }

    /// The most recent send failure not yet cleared by a successful send.
    func currentError() -> WebHostByteSinkError? {
      state.withLock(\.lastError)
    }

    var generation: UInt64 { state.withLock(\.generation) }

    var backlog: WebHostOutboundBudget { state.withLock(\.budget) }

    func beginConnection(connectionToken: UInt64?) {
      state.withLock { state in
        state.generation += 1
        // Unsent controls have no decoder baseline and have never reached a
        // socket. Preserve them across a capability boundary, including the
        // first declaration, instead of silently discarding clipboard/issues.
        state.pending = state.pending.compactMap { batch in
          if batch.isSurface {
            state.budget.release(batch.bytes.count)
            return nil
          }
          var retained = batch
          retained.connectionToken = connectionToken
          retained.generation = state.generation
          return retained
        }
        state.overflowed = false
        state.lastError = nil
      }
    }

    /// Check the record budget before encoding; byte admission follows once
    /// the encoded size is known. Presentations remain synchronous/nonblocking.
    func canEnqueue(connectionToken: UInt64?) -> Bool {
      let result = state.withLock { state -> (allowed: Bool, disconnect: Bool) in
        guard !state.overflowed else { return (false, false) }
        guard state.budget.records < WebHostOutboundBudget.recordLimit else {
          overflow(&state)
          return (false, true)
        }
        return (true, false)
      }
      if result.disconnect {
        Task { await sink.disconnect(connectionToken: connectionToken) }
      }
      return result.allowed
    }

    @discardableResult
    func enqueue(
      _ bytes: [UInt8], connectionToken: UInt64?, generation: UInt64? = nil,
      isSurface: Bool = false
    ) -> Bool {
      var accepted = false
      var disconnect = false
      let shouldStartDrain = state.withLock { state -> Bool in
        guard !state.overflowed else { return false }
        if let generation, generation != state.generation { return false }
        guard state.budget.admit(bytes.count) else {
          overflow(&state)
          disconnect = true
          return false
        }
        accepted = true
        state.pending.append(
          Batch(
            bytes: bytes, connectionToken: connectionToken, generation: state.generation,
            isSurface: isSurface))
        guard !state.isDraining else { return false }
        state.isDraining = true
        return true
      }
      if shouldStartDrain {
        Task { await self.drain() }
      }
      if disconnect {
        Task { await sink.disconnect(connectionToken: connectionToken) }
      }
      return accepted
    }

    private func discardPending(_ state: inout State) {
      for batch in state.pending { state.budget.release(batch.bytes.count) }
      state.pending.removeAll(keepingCapacity: false)
    }

    private func overflow(_ state: inout State) {
      state.overflowed = true
      state.lastError = .outboundBacklogExceeded
      discardPending(&state)
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
          do {
            try await sendWithTimeout(batch.bytes, connectionToken: batch.connectionToken)
            state.withLock { state in
              if batch.generation == state.generation, !state.overflowed {
                state.lastError = nil
              }
            }
          } catch let error as WebHostByteSinkError {
            recordFailure(error, generation: batch.generation)
            await sink.disconnect(connectionToken: batch.connectionToken)
          } catch {
            recordFailure(.sendFailed(String(describing: error)), generation: batch.generation)
            await sink.disconnect(connectionToken: batch.connectionToken)
          }
          state.withLock { $0.budget.release(batch.bytes.count) }
        case .finished(let waiters):
          for waiter in waiters {
            waiter.resume()
          }
          return
        }
      }
    }

    /// Records the failure and drops the queued batches behind it: they extend
    /// the encoding epoch the failed record broke, so delivering them would
    /// hand the decoder deltas against a baseline it never received. The next
    /// enqueue starts a fresh attempt.
    private func recordFailure(_ error: WebHostByteSinkError, generation: UInt64) {
      state.withLock { state in
        guard generation == state.generation, !state.overflowed else { return }
        state.lastError = error
        discardPending(&state)
        state.generation += 1
      }
    }

    private func sendWithTimeout(_ bytes: [UInt8], connectionToken: UInt64?) async throws {
      let sink = self.sink
      let timeoutNanoseconds = sendTimeoutNanoseconds
      try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask {
          try await sink.send(bytes, connectionToken: connectionToken)
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
#endif
