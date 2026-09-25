import SwiftTUICore

#if os(Android)
  @_spi(MainActorUtilities) import _Concurrency
#endif

extension RunLoop {
  package struct EventPump {
    var stream: AsyncStream<Void>
    var drainEvents: () -> [PumpedEvent]
    var hasPendingEvents: () -> Bool
    var cancel: () -> Void
    var scheduleDeadlineWake: @Sendable (Duration) -> Void
    /// Synchronously reads, parses, and enqueues whatever a
    /// ``SynchronousInputPulling`` reader's source holds, returning the number
    /// of events delivered. A no-op returning `0` for stream-adapter readers.
    /// Called at the start of each outer-loop turn and before each frame
    /// acquisition in a drain pass (plan 2026-09-24-001 §4D, STUI-618).
    var pullInput: @MainActor () -> Int = { 0 }
    /// Batches waiting in the pump buffer right now.
    var pendingBatchCount: () -> Int = { 0 }
    /// Enqueue instant of the oldest pending pump entry, if any.
    var oldestPendingArrival: () -> MonotonicInstant? = { nil }
  }

  package func makeEventPump(
    directWake: (@Sendable () -> Void)? = nil
  ) -> EventPump {
    let wakeNotifyingScheduler = scheduler as? any WakeNotifyingFrameScheduling
    #if os(Android)
      let directInputReader = terminalInputReader as? InjectedTerminalInputReader
      let directSignalReader = signalReader as? InProcessSignalReader
    #endif

    let completion = EventPumpCompletion(remainingStreams: 2)
    let buffer = EventPumpBuffer()
    let renderSuspensionDiagnostics = renderSuspensionDiagnostics
    let ingressDiagnostics = ingressDiagnostics
    var inputTask: Task<Void, Never>?
    var signalTask: Task<Void, Never>?
    let deadlineState = DeadlineWakeState()
    // A pulling reader (the WASI stdin ring) is drained synchronously by the
    // run loop and by the reader's own idle poll; the stream adapter stays
    // for blocking readers. Exactly one delivery path per reader (plan
    // 2026-09-24-001 §4D, STUI-618).
    let pullingReader = terminalInputReader as? any SynchronousInputPulling

    // The buffer and scheduler own the work; wake tokens carry no payload.
    // One pending wake suffices, including bursts during an in-flight frame.
    let stream = AsyncStream<Void>(bufferingPolicy: .bufferingNewest(1)) { continuation in
      deadlineState.setContinuation(continuation)

      if let pullingReader {
        pullingReader.installPullDelivery(
          InputPullDeliverySink(
            deliver: { event in
              renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
              if buffer.enqueue(.input(event)) {
                continuation.yield()
              }
              ingressDiagnostics.recordPumpEnqueue(depth: buffer.pendingBatchCount())
            },
            inputEnded: {
              if buffer.enqueue(.inputEnded) {
                continuation.yield()
              }
              completion.streamFinished(continuation)
            },
            recordSourceRead: { bytes, events in
              ingressDiagnostics.recordSourceRead(bytes: bytes, events: events)
            }
          )
        )
      } else {
        #if os(Android)
          if let directInputReader {
            directInputReader.installDirectHandler { event in
              renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
              if buffer.enqueue(.input(event)) {
                directWake?()
                continuation.yield()
              }
              ingressDiagnostics.recordPumpEnqueue(depth: buffer.pendingBatchCount())
            } onFinish: {
              // The host's stop finishes the reader. That ends input exactly
              // as the stream path's EOF does; without it the loop never wakes.
              if buffer.enqueue(.inputEnded) {
                continuation.yield()
              }
              completion.streamFinished(continuation)
            }
          } else {
            let inputEvents = terminalInputReader.inputEvents()
            inputTask = Task.immediate { @MainActor in
              for await event in inputEvents {
                renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
                if buffer.enqueue(.input(event)) {
                  continuation.yield()
                }
                ingressDiagnostics.recordPumpEnqueue(depth: buffer.pendingBatchCount())
              }
              if buffer.enqueue(.inputEnded) {
                continuation.yield()
              }
              completion.streamFinished(continuation)
            }
          }
        #else
          let inputEvents = terminalInputReader.inputEvents()
          inputTask = Task {
            for await event in inputEvents {
              renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
              if buffer.enqueue(.input(event)) {
                continuation.yield()
              }
              ingressDiagnostics.recordPumpEnqueue(depth: buffer.pendingBatchCount())
            }
            if buffer.enqueue(.inputEnded) {
              continuation.yield()
            }
            completion.streamFinished(continuation)
          }
        #endif
      }

      #if os(Android)
        if let directSignalReader {
          directSignalReader.installDirectHandler { signalName in
            if buffer.enqueue(.signal(signalName)) {
              directWake?()
              continuation.yield()
            }
          } onFinish: {
            completion.streamFinished(continuation)
          }
        } else {
          let signalEvents =
            signalReader?.events()
            ?? AsyncStream { continuation in
              continuation.finish()
            }
          signalTask = Task.immediate { @MainActor in
            for await signalName in signalEvents {
              if buffer.enqueue(.signal(signalName)) {
                continuation.yield()
              }
            }
            completion.streamFinished(continuation)
          }
        }
      #else
        let signalEvents =
          signalReader?.events()
          ?? AsyncStream { continuation in
            continuation.finish()
          }
        signalTask = Task {
          for await signalName in signalEvents {
            if buffer.enqueue(.signal(signalName)) {
              continuation.yield()
            }
          }
          completion.streamFinished(continuation)
        }
      #endif

      wakeNotifyingScheduler?.setWakeHandler {
        continuation.yield()
      }
    }

    let scheduleDeadlineWake: @Sendable (Duration) -> Void = { sleepDuration in
      deadlineState.schedule(sleepDuration: sleepDuration)
    }

    return EventPump(
      stream: stream,
      drainEvents: {
        buffer.drain()
      },
      hasPendingEvents: {
        buffer.hasPendingEvents()
      },
      cancel: {
        inputTask?.cancel()
        signalTask?.cancel()
        pullingReader?.uninstallPullDelivery()
        #if os(Android)
          directInputReader?.clearDirectHandler()
          directSignalReader?.clearDirectHandler()
        #endif
        deadlineState.cancel()
        wakeNotifyingScheduler?.setWakeHandler(nil)
      },
      scheduleDeadlineWake: scheduleDeadlineWake,
      pullInput: {
        guard let pullingReader else { return 0 }
        let delivered = pullingReader.pullPendingInput()
        ingressDiagnostics.recordPullDelivered(delivered)
        return delivered
      },
      pendingBatchCount: {
        buffer.pendingBatchCount()
      },
      oldestPendingArrival: {
        buffer.oldestPendingArrival()
      }
    )
  }

  package func drainPendingEvents(
    from eventPump: EventPump
  ) async -> [PumpedEvent] {
    // Turn-boundary pull: whatever a pulling reader's source holds is parsed
    // and enqueued here, synchronously, before this turn decides what to do.
    _ = eventPump.pullInput()
    var drainedEvents = eventPump.drainEvents()

    guard drainedEvents.allSatisfy(isCoalesciblePointerPumpedEvent) else {
      return drainedEvents
    }

    for _ in 0..<EventPumpTiming.coalescedPointerDrainYieldCount {
      await Task.yield()
      let additionalEvents = eventPump.drainEvents()
      guard !additionalEvents.isEmpty else {
        break
      }
      guard additionalEvents.allSatisfy(isCoalesciblePointerPumpedEvent) else {
        drainedEvents.append(contentsOf: additionalEvents)
        break
      }
      drainedEvents.append(contentsOf: additionalEvents)
    }

    return drainedEvents
  }

  package func drainPendingRenderEvents(
    from eventPump: EventPump,
    initialEvents: [PumpedEvent]
  ) -> RenderEventDrain {
    var events = initialEvents
    var coalescedEventBatches = 0

    while true {
      let additionalEvents = eventPump.drainEvents()
      guard !additionalEvents.isEmpty else {
        break
      }
      coalescedEventBatches += 1
      events.append(contentsOf: additionalEvents)
    }

    return RenderEventDrain(
      events: events,
      coalescedEventBatches: coalescedEventBatches
    )
  }

  /// Drains and renders whatever the pump holds, synchronously.
  ///
  /// This is the run loop's only re-entry point from outside its own task (the
  /// Android host's `directWake`), so it re-establishes the ambient
  /// registration scope itself rather than inheriting one — see
  /// ``RunLoop/withRuntimeRegistrationScope(_:)`` for what silently breaks
  /// without it.
  package func processPendingEventsSynchronously(
    from eventPump: EventPump,
    renderedFrames: inout Int
  ) throws -> RunLoopExitReason? {
    var frames = renderedFrames
    defer { renderedFrames = frames }
    return try withRuntimeRegistrationScope {
      try processPendingEventsSynchronouslyInScope(
        from: eventPump,
        renderedFrames: &frames
      )
    }
  }

  private func processPendingEventsSynchronouslyInScope(
    from eventPump: EventPump,
    renderedFrames: inout Int
  ) throws -> RunLoopExitReason? {
    if let exitReason = consumeProgrammaticTerminationRequest() {
      return exitReason
    }

    _ = eventPump.pullInput()
    let pendingEvents = eventPump.drainEvents()
    guard !pendingEvents.isEmpty else {
      try renderPendingFrames(renderedFrames: &renderedFrames, eventPump: eventPump)
      return consumeProgrammaticTerminationRequest()
    }

    let renderEventDrain = drainPendingRenderEvents(
      from: eventPump,
      initialEvents: pendingEvents
    )
    progressProbe?.record(
      .eventDrain,
      frameNumber: renderedFrames + 1,
      eventCount: renderEventDrain.events.count,
      coalescedEventBatches: renderEventDrain.coalescedEventBatches
    )
    pendingCoalescedEventBatches += renderEventDrain.coalescedEventBatches

    var handledNonExitEvent = false
    for pumpedEvent in renderEventDrain.events {
      let hadReadyFrameBeforeEvent = scheduler.hasPendingFrame(at: .now())
      if let exitReason = handle(pumpedEvent.event, arrival: pumpedEvent.arrival) {
        let shouldFlushBeforeExit =
          handledNonExitEvent
          || (hadReadyFrameBeforeEvent
            && {
              if case .signal = exitReason {
                return true
              }
              return false
            }())
        if shouldFlushBeforeExit {
          try renderPendingFrames(
            renderedFrames: &renderedFrames, eventPump: eventPump, appliesWorkBudget: false)
        }
        if let programmatic = consumeProgrammaticTerminationRequest() {
          return programmatic
        }
        if terminationDisposition(for: exitReason) == .cancel {
          scheduler.requestInvalidation(of: [rootIdentity])
          handledNonExitEvent = true
          continue
        }
        return exitReason
      }
      handledNonExitEvent = true
    }

    try renderPendingFrames(renderedFrames: &renderedFrames, eventPump: eventPump)
    return consumeProgrammaticTerminationRequest()
  }

}
