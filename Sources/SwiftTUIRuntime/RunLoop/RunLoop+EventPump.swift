import SwiftTUICore

extension RunLoop {
  package struct EventPump {
    var stream: AsyncStream<Void>
    var drainEvents: () -> [RuntimeEvent]
    var hasPendingEvents: () -> Bool
    var cancel: () -> Void
    var scheduleDeadlineWake: @Sendable (Duration) -> Void
  }

  package func makeEventPump() -> EventPump {
    let inputEvents = terminalInputReader.inputEvents()
    let signalEvents =
      signalReader?.events()
      ?? AsyncStream { continuation in
        continuation.finish()
      }
    let wakeNotifyingScheduler = scheduler as? any WakeNotifyingFrameScheduling

    let completion = EventPumpCompletion(remainingStreams: 2)
    let buffer = EventPumpBuffer()
    let renderSuspensionDiagnostics = renderSuspensionDiagnostics
    var inputTask: Task<Void, Never>?
    var signalTask: Task<Void, Never>?
    let deadlineState = DeadlineWakeState()

    let stream = AsyncStream<Void> { continuation in
      deadlineState.setContinuation(continuation)

      inputTask = Task {
        for await event in inputEvents {
          renderSuspensionDiagnostics.recordInputEventQueuedIfSuspended()
          if buffer.enqueue(.input(event)) {
            continuation.yield()
          }
        }
        completion.streamFinished(continuation)
      }

      signalTask = Task {
        for await signalName in signalEvents {
          if buffer.enqueue(.signal(signalName)) {
            continuation.yield()
          }
        }
        completion.streamFinished(continuation)
      }

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

}
