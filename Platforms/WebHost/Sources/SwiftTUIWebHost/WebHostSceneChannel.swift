// Compiled out on Windows: the web host is deliberately absent from the
// first Windows release (Stage 5.3 of the Windows plan, option (i)) —
// its socket layer is POSIX-bound and the umbrella's dependency edge is
// platform-conditional.
#if !os(Windows)
  /// A tagged inbound event from the client side of a WebHost scene channel.
  ///
  /// A raw `[UInt8]` chunk stream lost the one fact the reader needs: *which
  /// connection* produced each chunk. Without it, a reconnecting client's bytes
  /// could be appended onto the previous client's partial record inside the
  /// parser, and a callback arriving late from a closed client could mutate the
  /// session that replaced it.
  package enum WebHostInboundEvent: Sendable {
    case connectionOpened(token: UInt64)
    case bytes(token: UInt64, [UInt8])
    case connectionClosed(token: UInt64)
    case shutdown
  }

  /// One inbound chunk that was refused, and why.
  package struct WebHostDiscardedInboundChunk: Equatable, Sendable {
    package enum Reason: String, Equatable, Sendable {
      /// The chunk's connection had already been superseded when it arrived.
      case staleAtIngress = "stale-at-ingress"
      /// The chunk arrived on the then-current connection but was still queued
      /// when that connection was superseded.
      case staleAtConsumption = "stale-at-consumption"
      /// A partial record the parser still held when a new connection opened.
      case connectionBoundary = "connection-boundary"
      /// The channel had already shut down.
      case terminal
    }

    package var token: UInt64
    package var bytes: [UInt8]
    package var reason: Reason

    package init(
      token: UInt64,
      bytes: [UInt8],
      reason: Reason
    ) {
      self.token = token
      self.bytes = bytes
      self.reason = reason
    }
  }

  /// The channel's observable state, consumed as an interval by tests and the
  /// conformance oracle: counters and record logs reset on read, gauges do not.
  package struct WebHostChannelObservations: Sendable {
    package var suppressedSurfaceRecords: [[UInt8]]
    package var discardedInboundChunks: [WebHostDiscardedInboundChunk]
    package var detachedNonSurfaceBacklogCount: Int
    package var detachedNonSurfaceBacklogBytes: Int
    package var refreshRequestCount: Int
    package var capsProcessedCount: Int
    package var ignoredStaleCallbackCount: Int
    package var currentToken: UInt64?
    package var lastIssuedToken: UInt64
    package var phase: WebHostSceneChannel.Phase
    package var sceneInputFinished: Bool
  }

  /// The scene's byte channel: one long-lived scene input stream, and a client
  /// connection that comes and goes beneath it.
  ///
  /// Three properties are load-bearing and each replaced a defect:
  ///
  /// 1. **Detached output drops surface records.** A surface record buffered
  ///    while no client is attached is worthless to whoever attaches next — a
  ///    delta names a baseline the fresh decoder does not have, and even a full
  ///    frame belongs to the encoding epoch that ended with the old client. The
  ///    backlog therefore retains only non-surface records (clipboard, runtime
  ///    issues), bounded, and is flushed in order on attach. Blank beats stale.
  /// 2. **A client close is connection-local.** It transitions the channel to
  ///    detached but must never finish the scene-wide input continuation:
  ///    finishing it terminates `WebSocketInputReader` for good, so a
  ///    reattaching client's capability declaration could never be read and the
  ///    session could never leave its pre-capabilities phase. Only
  ///    `shutdown()` finishes scene input.
  /// 3. **Every connection carries a monotonically increasing token.** Input,
  ///    close, and capability callbacks are accepted only while their token
  ///    still names the current connection, so a late callback from a replaced
  ///    client cannot detach, activate, or inject input into its successor.
  package actor WebHostSceneChannel: WebHostByteSink, WebHostByteSource {
    /// Where a connection stands relative to its capability declaration.
    ///
    /// A newly attached client is *pre-capabilities*: it receives non-surface
    /// records immediately, but every surface record is dropped until its
    /// declaration re-anchors the encoder, because anything sent earlier belongs
    /// to the previous epoch.
    package enum Phase: String, Equatable, Sendable {
      case detached
      case preCapabilities = "pre-capabilities"
      case active
      case terminal
    }

    /// Cap on records retained while detached. Surface records never enter this
    /// backlog, so it bounds clipboard and runtime-issue records only. At the
    /// cap the oldest record is dropped: for both kinds the newest is the one
    /// worth delivering.
    package static let detachedNonSurfaceBacklogLimit = 32

    private static let surfaceRecordPrefix = Array("\u{001E}surface:".utf8)

    nonisolated let inboundStream: AsyncStream<WebHostInboundEvent>
    private nonisolated let inboundContinuation: AsyncStream<WebHostInboundEvent>.Continuation

    private var outputContinuation: AsyncStream<WebHostSocketMessage>.Continuation?
    private var detachedNonSurfaceBacklog: [[UInt8]] = []
    private var phase: Phase = .detached
    private var currentToken: UInt64?
    private var lastIssuedToken: UInt64 = 0
    private var sceneInputFinished = false
    private var receiveTasks: [Task<Void, Never>] = []
    private var processedInboundCallbacks: UInt64 = 0
    private var yieldedInboundEvents: UInt64 = 0
    private var yieldedOutputRecords: UInt64 = 0
    private var inboundCallbackWaiters:
      [(target: UInt64, continuation: CheckedContinuation<Void, Never>)] = []

    private var suppressedSurfaceRecords: [[UInt8]] = []
    private var discardedInboundChunks: [WebHostDiscardedInboundChunk] = []
    private var refreshRequestCount = 0
    private var capsProcessedCount = 0
    private var ignoredStaleCallbackCount = 0

    package init() {
      var continuation: AsyncStream<WebHostInboundEvent>.Continuation?
      inboundStream = AsyncStream { continuation = $0 }
      inboundContinuation = continuation!
    }

    package nonisolated func inboundEvents() -> AsyncStream<WebHostInboundEvent> {
      inboundStream
    }

    package func currentConnectionToken() -> UInt64? {
      currentToken
    }

    /// Non-consuming: reading a gauge must not clear the interval counters
    /// `consumeObservations()` owns.
    package func lastIssuedConnectionToken() -> UInt64 {
      lastIssuedToken
    }

    /// Monotonic count of client messages this channel has handled.
    ///
    /// A deterministic synchronization point for tests: a client message travels
    /// a real receive task, so "has it been handled yet" cannot be answered by a
    /// fixed number of task yields — under load that budget is a coin flip. Read
    /// this to capture a baseline, then await `waitForProcessedInboundCallbacks`.
    package func processedInboundCallbackCount() -> UInt64 {
      processedInboundCallbacks
    }

    /// Suspends until this channel has handled at least `target` client messages.
    ///
    /// The signal half of the gauge above, and the reason no caller has to poll:
    /// a waiter is resumed by `receive` itself. Polling would be worse than slow,
    /// it would be wrong — `Task.yield()` re-enqueues the waiter without freeing
    /// its thread, so a turn budget can expire while the receive task has not run
    /// once, and the caller would conclude "not handled" about a live message.
    ///
    /// `shutdown()` resumes every outstanding waiter: after it, no further
    /// callback can arrive, so suspending on one would strand the caller.
    package func waitForProcessedInboundCallbacks(
      atLeast target: UInt64
    ) async {
      guard processedInboundCallbacks < target, phase != .terminal else {
        return
      }
      await withCheckedContinuation { continuation in
        inboundCallbackWaiters.append((target: target, continuation: continuation))
      }
    }

    private func resumeMaturedInboundCallbackWaiters() {
      guard !inboundCallbackWaiters.isEmpty else {
        return
      }
      let matured = inboundCallbackWaiters.filter { processedInboundCallbacks >= $0.target }
      inboundCallbackWaiters.removeAll { processedInboundCallbacks >= $0.target }
      for waiter in matured {
        waiter.continuation.resume()
      }
    }

    /// Monotonic count of tagged events yielded onto the scene input stream.
    ///
    /// The second half of the same deterministic story as
    /// `processedInboundCallbackCount()`: a consumer that buffers this stream can
    /// tell whether an event it has not seen yet is still in flight, instead of
    /// guessing from a turn budget.
    package func yieldedInboundEventCount() -> UInt64 {
      yieldedInboundEvents
    }

    /// Monotonic count of data records yielded onto a client's output stream.
    ///
    /// The output-direction twin of `yieldedInboundEventCount()`. A consumer that
    /// records deliveries on its own task cannot otherwise distinguish "nothing
    /// was delivered" from "the delivery has not been picked up yet", and a turn
    /// budget is not a bound on that: `Task.yield()` re-enqueues without freeing
    /// the thread, so thousands of turns can pass in milliseconds while the
    /// consuming task never runs. This gauge is the condition to wait on instead.
    ///
    /// Counts data records only. Close messages are transport framing, and
    /// suppressed or detached-dropped surface records are never yielded at all.
    package func yieldedOutputRecordCount() -> UInt64 {
      yieldedOutputRecords
    }

    package func recordDiscardedInboundChunk(
      _ chunk: WebHostDiscardedInboundChunk
    ) {
      discardedInboundChunks.append(chunk)
    }

    package func send(
      _ bytes: [UInt8]
    ) async throws {
      switch phase {
      case .terminal:
        return
      case .detached:
        guard !Self.isSurfaceRecord(bytes) else {
          return
        }
        if detachedNonSurfaceBacklog.count >= Self.detachedNonSurfaceBacklogLimit {
          detachedNonSurfaceBacklog.removeFirst(
            detachedNonSurfaceBacklog.count - Self.detachedNonSurfaceBacklogLimit + 1
          )
        }
        detachedNonSurfaceBacklog.append(bytes)
      case .preCapabilities:
        guard !Self.isSurfaceRecord(bytes) else {
          // Observed as suppression, never as delivery: the record belongs to
          // the epoch that ended with the previous client.
          suppressedSurfaceRecords.append(bytes)
          return
        }
        yieldOutput(bytes)
      case .active:
        yieldOutput(bytes)
      }
    }

    /// The one place a data record reaches a client, so the delivery gauge cannot
    /// drift from what was actually yielded.
    private func yieldOutput(
      _ bytes: [UInt8]
    ) {
      guard let outputContinuation else {
        return
      }
      yieldedOutputRecords += 1
      outputContinuation.yield(.data(bytes))
    }

    package func attach(
      client: AsyncStream<WebHostSocketMessage>
    ) -> AsyncStream<WebHostSocketMessage> {
      guard phase != .terminal else {
        return AsyncStream { $0.finish() }
      }

      if let previous = outputContinuation {
        previous.yield(.normalClose)
        previous.finish()
        outputContinuation = nil
      }

      lastIssuedToken += 1
      let token = lastIssuedToken
      currentToken = token
      phase = .preCapabilities

      return AsyncStream { continuation in
        outputContinuation = continuation
        yieldInbound(.connectionOpened(token: token))
        for bytes in detachedNonSurfaceBacklog {
          yieldOutput(bytes)
        }
        detachedNonSurfaceBacklog.removeAll(keepingCapacity: true)

        // The receive loop deliberately outlives detachment. Bytes already in
        // flight when a client is replaced still have to reach the reader tagged
        // with their originating connection, or they vanish silently instead of
        // being refused — and "refused, with a reason" is the whole point of the
        // tagged stream. The task ends when the client stream finishes, and
        // `shutdown()` cancels whatever is left.
        // This `Task` inherits the channel's actor isolation, so both calls are
        // same-actor and take no `await`. The `onTermination` closure below is a
        // different story: it is not isolated, so its call does.
        let task = Task {
          for await message in client {
            self.receive(message, token: token)
          }
          self.connectionDidEnd(token: token)
        }
        receiveTasks.append(task)

        continuation.onTermination = { _ in
          Task {
            await self.connectionDidEnd(token: token)
          }
        }
      }
    }

    /// Applies a client's capability declaration, or refuses it.
    ///
    /// One atomic actor step, in this order: the token must still name the
    /// current connection and that connection must still be pre-capabilities;
    /// then the encoder re-anchors, the session becomes surface-active, and a
    /// refresh is requested so the first deliverable surface record is a
    /// post-declaration keyframe. Because `send` is isolated to the same actor,
    /// no surface record can slip between the re-anchor and the activation.
    @discardableResult
    package func applyCapabilities(
      token: UInt64,
      reanchor: @Sendable () -> Void,
      requestRefresh: @Sendable () -> Void
    ) -> Bool {
      guard token == currentToken else {
        ignoredStaleCallbackCount += 1
        return false
      }
      guard phase == .preCapabilities else {
        // A second declaration on the same connection is not an epoch: the
        // client declares once, before any surface record is deliverable.
        return false
      }
      reanchor()
      phase = .active
      capsProcessedCount += 1
      requestRefresh()
      refreshRequestCount += 1
      return true
    }

    /// The sole terminal transition, and idempotent.
    ///
    /// Every `WebHostServerSession.stop()` path must reach this before or with
    /// the server stop, or the reader and output tasks outlive the session.
    package func shutdown() {
      guard phase != .terminal else {
        return
      }
      phase = .terminal
      currentToken = nil
      outputContinuation?.yield(.normalClose)
      outputContinuation?.finish()
      outputContinuation = nil
      detachedNonSurfaceBacklog.removeAll(keepingCapacity: true)
      for task in receiveTasks {
        task.cancel()
      }
      receiveTasks.removeAll(keepingCapacity: true)
      yieldInbound(.shutdown)
      inboundContinuation.finish()
      sceneInputFinished = true
      let stranded = inboundCallbackWaiters
      inboundCallbackWaiters.removeAll()
      for waiter in stranded {
        waiter.continuation.resume()
      }
    }

    package func consumeObservations() -> WebHostChannelObservations {
      let observations = WebHostChannelObservations(
        suppressedSurfaceRecords: suppressedSurfaceRecords,
        discardedInboundChunks: discardedInboundChunks,
        detachedNonSurfaceBacklogCount: detachedNonSurfaceBacklog.count,
        detachedNonSurfaceBacklogBytes: detachedNonSurfaceBacklog.reduce(0) { $0 + $1.count },
        refreshRequestCount: refreshRequestCount,
        capsProcessedCount: capsProcessedCount,
        ignoredStaleCallbackCount: ignoredStaleCallbackCount,
        currentToken: currentToken,
        lastIssuedToken: lastIssuedToken,
        phase: phase,
        sceneInputFinished: sceneInputFinished
      )
      suppressedSurfaceRecords.removeAll(keepingCapacity: true)
      discardedInboundChunks.removeAll(keepingCapacity: true)
      refreshRequestCount = 0
      capsProcessedCount = 0
      ignoredStaleCallbackCount = 0
      return observations
    }

    private func receive(
      _ message: WebHostSocketMessage,
      token: UInt64
    ) {
      processedInboundCallbacks += 1
      defer { resumeMaturedInboundCallbackWaiters() }
      guard phase != .terminal else {
        if case .data(let bytes) = message {
          discardedInboundChunks.append(
            .init(token: token, bytes: bytes, reason: .terminal))
        }
        return
      }

      switch message {
      case .text(let text):
        // Stale bytes are still yielded, tagged: the reader is the one place
        // that knows whether a chunk was current when it arrived, and refusing
        // here would erase the distinction between the two staleness reasons.
        yieldInbound(.bytes(token: token, Array(text.utf8)))
      case .data(let bytes):
        yieldInbound(.bytes(token: token, bytes))
      case .close(let code, let reason):
        guard token == currentToken else {
          // A late close from a replaced client must not detach its successor.
          ignoredStaleCallbackCount += 1
          return
        }
        outputContinuation?.yield(.close(code: code, reason: reason))
        detachCurrentConnection(token: token)
      }
    }

    /// The connection's receive loop ended (stream finished or output
    /// terminated). Unlike an explicit close message this is ordinary teardown,
    /// so retiring an already-retired token is silent rather than an ignored
    /// stale callback.
    private func connectionDidEnd(
      token: UInt64
    ) {
      guard phase != .terminal, token == currentToken else {
        return
      }
      detachCurrentConnection(token: token)
    }

    private func detachCurrentConnection(
      token: UInt64
    ) {
      currentToken = nil
      phase = .detached
      outputContinuation?.finish()
      outputContinuation = nil
      yieldInbound(.connectionClosed(token: token))
    }

    private func yieldInbound(
      _ event: WebHostInboundEvent
    ) {
      yieldedInboundEvents += 1
      inboundContinuation.yield(event)
    }

    private static func isSurfaceRecord(
      _ bytes: [UInt8]
    ) -> Bool {
      bytes.count >= surfaceRecordPrefix.count
        && bytes.starts(with: surfaceRecordPrefix)
    }
  }
#endif
