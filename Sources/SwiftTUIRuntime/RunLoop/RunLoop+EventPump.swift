import SwiftTUICore

#if os(Android)
  @_spi(MainActorUtilities) import _Concurrency
#endif

extension RunLoop {
  package struct EventPump {
    var stream: AsyncStream<Void>
    var drainEvents: () -> [RuntimeEvent]
    var hasPendingEvents: () -> Bool
    var cancel: () -> Void
    var scheduleDeadlineWake: @Sendable (Duration) -> Void
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
    var inputTask: Task<Void, Never>?
    var signalTask: Task<Void, Never>?
    let deadlineState = DeadlineWakeState()

    let stream = AsyncStream<Void> { continuation in
      deadlineState.setContinuation(continuation)

      #if os(Android)
        if let directInputReader {
          let pendingEvents = directInputReader.installDirectHandler { event in
            renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
            if buffer.enqueue(.input(event)) {
              directWake?()
              continuation.yield()
            }
          }
          for event in pendingEvents {
            renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
            if buffer.enqueue(.input(event)) {
              directWake?()
              continuation.yield()
            }
          }
        } else {
          let inputEvents = terminalInputReader.inputEvents()
          inputTask = Task.immediate { @MainActor in
            for await event in inputEvents {
              renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
              if buffer.enqueue(.input(event)) {
                continuation.yield()
              }
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
          }
          completion.streamFinished(continuation)
        }
      #endif

      #if os(Android)
        if let directSignalReader {
          directSignalReader.installDirectHandler { signalName in
            if buffer.enqueue(.signal(signalName)) {
              directWake?()
              continuation.yield()
            }
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
        #if os(Android)
          directInputReader?.clearDirectHandler()
          directSignalReader?.clearDirectHandler()
        #endif
        deadlineState.cancel()
        wakeNotifyingScheduler?.setWakeHandler(nil)
      },
      scheduleDeadlineWake: scheduleDeadlineWake
    )
  }

  package func drainPendingEvents(
    from eventPump: EventPump
  ) async -> [RuntimeEvent] {
    var drainedEvents = eventPump.drainEvents()

    guard drainedEvents.allSatisfy(isCoalesciblePointerRuntimeEvent) else {
      return drainedEvents
    }

    for _ in 0..<EventPumpTiming.coalescedPointerDrainYieldCount {
      await Task.yield()
      let additionalEvents = eventPump.drainEvents()
      guard !additionalEvents.isEmpty else {
        break
      }
      guard additionalEvents.allSatisfy(isCoalesciblePointerRuntimeEvent) else {
        drainedEvents.append(contentsOf: additionalEvents)
        break
      }
      drainedEvents.append(contentsOf: additionalEvents)
    }

    return drainedEvents
  }

  package func drainPendingRenderEvents(
    from eventPump: EventPump,
    initialEvents: [RuntimeEvent]
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

  package func processPendingEventsSynchronously(
    from eventPump: EventPump,
    renderedFrames: inout Int
  ) throws -> RunLoopExitReason? {
    let pendingEvents = eventPump.drainEvents()
    guard !pendingEvents.isEmpty else {
      try renderPendingFrames(renderedFrames: &renderedFrames)
      return nil
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
    for event in renderEventDrain.events {
      let hadReadyFrameBeforeEvent = scheduler.hasPendingFrame(at: .now())
      if let exitReason = handle(event) {
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
          try renderPendingFrames(renderedFrames: &renderedFrames)
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

    try renderPendingFrames(renderedFrames: &renderedFrames)
    return nil
  }

}
