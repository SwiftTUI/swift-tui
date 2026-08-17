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
      var encodingState: HostWireEncodingState
      var wireCapabilities: HostWireCapabilities
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
      _ capabilities: HostWireCapabilities
    ) {
      state.withLock { state in
        state.wireCapabilities = capabilities
        state.encodingState = capabilities.negotiatedEncodingState()
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
      let bytes = state.withLock { state -> [UInt8] in
        guard let retained = state.lastPresentedFrame else {
          return []
        }
        let background = state.renderStyle.appearance.backgroundColor
        switch retained {
        case .raster(let surface):
          return Array(
            WebSurfaceFrameEncoder.encode(
              surface,
              damage: nil,
              fallbackBackground: background,
              state: &state.encodingState
            ).utf8)
        case .semantic(let frame):
          return Array(
            WebSurfaceFrameEncoder.encode(
              frame,
              fallbackBackground: background,
              state: &state.encodingState
            ).utf8)
        }
      }
      // A refresh is best-effort by construction: a transport already carrying a
      // send failure has nothing useful to add by throwing from a capability
      // declaration.
      try? sendBytes(bytes)
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
        state.lastPresentedFrame = .raster(surface)
        return Array(
          WebSurfaceFrameEncoder.encode(
            surface,
            damage: nil,
            fallbackBackground: state.renderStyle.appearance.backgroundColor,
            state: &state.encodingState
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
        state.lastPresentedFrame = .semantic(frame)
        return Array(
          WebSurfaceFrameEncoder.encode(
            frame,
            fallbackBackground: state.renderStyle.appearance.backgroundColor,
            state: &state.encodingState
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
    /// Throws the most recent send failure not yet cleared by a successful
    /// send, if any. This is the awaitable completion signal callers use
    /// instead of blocking inside `present`.
    package func drain() async throws {
      await pump.waitUntilIdle()
      if let error = pump.currentError() {
        throw error
      }
    }

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

    private func sendBytes(
      _ bytes: [UInt8]
    ) throws {
      guard !bytes.isEmpty else {
        return
      }
      // Hand the batch off without blocking; the pump's drain task does the
      // sending and callers await `drain()` to learn when it finished. A prior
      // send failure deliberately does NOT throw here: `present` errors
      // propagate out of the hosting run loop and end the scene, so surfacing
      // a stale pump error from the next present turned one transient stall
      // (a 10 s send timeout) into a permanently dead session on a client
      // that has no reconnect. The pump drops the broken epoch and recovers
      // instead — see `ByteSinkPump`.
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
  /// A send failure is connection-scoped, not fatal. The failed batch and
  /// everything queued behind it are dropped — they extend an encoding epoch
  /// the peer can no longer decode once one record is missing — the error is
  /// retained for `waitUntilIdle()`/`currentError()` reporting, and the next
  /// enqueue starts a fresh attempt; a later successful send clears the error.
  /// Wire consistency self-heals through the existing machinery: the browser
  /// decoder detects a broken delta baseline and requests a resync, and a
  /// reconnecting client re-anchors to a keyframe via its capability
  /// declaration. The previous design latched the first error forever and
  /// skipped every later batch, so one stalled send permanently froze the
  /// session. The per-send timeout still applies, but it races *inside* the
  /// drain task and so never blocks a presenting caller.
  private final class ByteSinkPump: Sendable {
    private enum DrainStep {
      case batch([UInt8])
      case finished([CheckedContinuation<Void, Never>])
    }

    private struct State {
      var pending: [[UInt8]] = []
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
          do {
            try await sendWithTimeout(batch)
            state.withLock { state in
              state.lastError = nil
            }
          } catch let error as WebHostByteSinkError {
            recordFailure(error)
          } catch {
            recordFailure(.sendFailed(String(describing: error)))
          }
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
    private func recordFailure(_ error: WebHostByteSinkError) {
      state.withLock { state in
        state.lastError = error
        state.pending.removeAll(keepingCapacity: false)
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
#endif
