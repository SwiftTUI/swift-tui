import SwiftTUICore
import Synchronization

/// Manages a single deadline-wake task that sleeps until a future deadline
/// and then yields into the event pump stream.
///
/// All mutable state is guarded by a `Mutex`, making this type safe for
/// concurrent access from multiple tasks.
package final class DeadlineWakeState: Sendable {
  private struct State: Sendable {
    var continuation: AsyncStream<Void>.Continuation?
    var task: Task<Void, Never>?
  }

  private let state = Mutex(State())

  func setContinuation(_ continuation: AsyncStream<Void>.Continuation) {
    state.withLock { $0.continuation = continuation }
  }

  func schedule(sleepDuration: Duration) {
    state.withLock { state in
      state.task?.cancel()
      let continuation = state.continuation
      state.task = Task.detached {
        try? await Task.sleep(for: sleepDuration)
        guard !Task.isCancelled else { return }
        continuation?.yield()
      }
    }
  }

  func cancel() {
    state.withLock { $0.task?.cancel() }
  }
}

extension RunLoop {
  enum EventPumpTiming {
    static var coalescedPointerDrainYieldCount: Int { 4 }
  }

  package struct RenderEventDrain {
    var events: [RuntimeEvent]
    var coalescedEventBatches: Int
  }

  package final class EventPumpCompletion: Sendable {
    private let remainingStreams: Mutex<Int>

    init(remainingStreams: Int) {
      self.remainingStreams = Mutex(remainingStreams)
    }

    func streamFinished<Element>(
      _ continuation: AsyncStream<Element>.Continuation
    ) {
      let shouldFinish = remainingStreams.withLock { remainingStreams in
        remainingStreams -= 1
        return remainingStreams == 0
      }
      if shouldFinish {
        continuation.finish()
      }
    }
  }

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

  package func isCoalesciblePointerRuntimeEvent(
    _ event: RuntimeEvent
  ) -> Bool {
    guard case .input(.mouse(let mouseEvent)) = event else {
      return false
    }
    return mouseEvent.isCoalescible
  }
}
