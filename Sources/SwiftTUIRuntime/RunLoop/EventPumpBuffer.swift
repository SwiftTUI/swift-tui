import SwiftTUICore
import Synchronization

/// Thread-safe staging buffer for events flowing into the run loop's event
/// pump. Coalescible pointer events are merged in place so a burst of mouse
/// motion collapses to a single batch.
///
/// Every enqueued event is wrapped in an ``InputArrival`` envelope stamped at
/// enqueue — the moment the runtime first sees the event. Merging fuses the
/// envelopes rather than discarding one, so a merged burst still reports how
/// many raw arrivals it stands for.
///
/// Declared at module scope (rather than nested in the generic
/// `RunLoop<State, Content>`) so its metatype stays `Sendable`: the buffer is
/// captured by the `@Sendable` direct-handler closures in `makeEventPump`, and
/// a generic-nested type would drag the non-`Sendable` `Content.Type` metatype
/// across that isolation boundary (see `RunLoop+EventPump.swift`).
package final class EventPumpBuffer: Sendable {
  private struct BufferState {
    var pendingBatches: [[PumpedEvent]] = []
    var nextArrivalID: UInt64 = 0
  }

  private let state = Mutex(BufferState())
  /// Read-time clock. Injectable so latency tests can author arrival instants
  /// instead of racing the wall clock; production reads the monotonic clock.
  private let clock: @Sendable () -> MonotonicInstant

  package init(clock: @escaping @Sendable () -> MonotonicInstant = { .now() }) {
    self.clock = clock
  }

  @discardableResult
  func enqueue(_ event: RuntimeEvent) -> Bool {
    let arrivalInstant = clock()
    return state.withLock { state in
      let arrival = InputArrival(id: state.nextArrivalID, arrival: arrivalInstant)
      state.nextArrivalID &+= 1

      if let lastBatch = state.pendingBatches.last,
        canAppendToBatch(event, batch: lastBatch)
      {
        let batchIndex = state.pendingBatches.count - 1
        if let lastEntry = state.pendingBatches[batchIndex].last,
          let mergedEvent = mergedEvent(lastEntry.event, with: event)
        {
          state.pendingBatches[batchIndex][state.pendingBatches[batchIndex].count - 1] =
            PumpedEvent(
              event: mergedEvent,
              arrival: lastEntry.arrival.fused(with: arrival)
            )
        } else {
          state.pendingBatches[batchIndex].append(
            PumpedEvent(event: event, arrival: arrival)
          )
        }
        return false
      }

      state.pendingBatches.append([PumpedEvent(event: event, arrival: arrival)])
      return true
    }
  }

  func drain() -> [PumpedEvent] {
    state.withLock { state in
      guard !state.pendingBatches.isEmpty else {
        return []
      }
      return state.pendingBatches.removeFirst()
    }
  }

  func hasPendingEvents() -> Bool {
    state.withLock { !$0.pendingBatches.isEmpty }
  }

  private func mergedEvent(
    _ current: RuntimeEvent,
    with next: RuntimeEvent
  ) -> RuntimeEvent? {
    switch (current, next) {
    case (.input(.mouse(let currentMouseEvent)), .input(.mouse(let nextMouseEvent))):
      guard let mergedMouseEvent = currentMouseEvent.merged(with: nextMouseEvent) else {
        return nil
      }
      return .input(.mouse(mergedMouseEvent))
    case (.input, _), (.inputEnded, _), (.signal, _):
      return nil
    }
  }

  private func canAppendToBatch(
    _ event: RuntimeEvent,
    batch: [PumpedEvent]
  ) -> Bool {
    isCoalesciblePointerEvent(event)
      && !batch.isEmpty
      && batch.allSatisfy { isCoalesciblePointerEvent($0.event) }
  }

  private func isCoalesciblePointerEvent(
    _ event: RuntimeEvent
  ) -> Bool {
    switch event {
    case .input(.mouse(let mouseEvent)):
      return mouseEvent.isCoalescible
    case .input, .inputEnded, .signal:
      return false
    }
  }
}
