import Synchronization

/// Thread-safe staging buffer for events flowing into the run loop's event
/// pump. Coalescible pointer events are merged in place so a burst of mouse
/// motion collapses to a single batch.
///
/// Declared at module scope (rather than nested in the generic
/// `RunLoop<State, Content>`) so its metatype stays `Sendable`: the buffer is
/// captured by the `@Sendable` direct-handler closures in `makeEventPump`, and
/// a generic-nested type would drag the non-`Sendable` `Content.Type` metatype
/// across that isolation boundary (see `RunLoop+EventPump.swift`).
package final class EventPumpBuffer: Sendable {
  private struct BufferState {
    var pendingBatches: [[RuntimeEvent]] = []
  }

  private let state = Mutex(BufferState())

  func enqueue(_ event: RuntimeEvent) -> Bool {
    state.withLock { state in
      if let lastBatch = state.pendingBatches.last,
        canAppendToBatch(event, batch: lastBatch)
      {
        let batchIndex = state.pendingBatches.count - 1
        if let lastEvent = state.pendingBatches[batchIndex].last,
          let mergedEvent = mergedEvent(lastEvent, with: event)
        {
          state.pendingBatches[batchIndex][state.pendingBatches[batchIndex].count - 1] =
            mergedEvent
        } else {
          state.pendingBatches[batchIndex].append(event)
        }
        return false
      }

      state.pendingBatches.append([event])
      return true
    }
  }

  func drain() -> [RuntimeEvent] {
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
    guard case .input(.mouse(let currentMouseEvent)) = current,
      case .input(.mouse(let nextMouseEvent)) = next,
      let mergedMouseEvent = currentMouseEvent.merged(with: nextMouseEvent)
    else {
      return nil
    }

    return .input(.mouse(mergedMouseEvent))
  }

  private func canAppendToBatch(
    _ event: RuntimeEvent,
    batch: [RuntimeEvent]
  ) -> Bool {
    isCoalesciblePointerEvent(event)
      && !batch.isEmpty
      && batch.allSatisfy(isCoalesciblePointerEvent)
  }

  private func isCoalesciblePointerEvent(
    _ event: RuntimeEvent
  ) -> Bool {
    guard case .input(.mouse(let mouseEvent)) = event else {
      return false
    }
    return mouseEvent.isCoalescible
  }
}
