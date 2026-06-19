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

  package func isCoalesciblePointerRuntimeEvent(
    _ event: RuntimeEvent
  ) -> Bool {
    guard case .input(.mouse(let mouseEvent)) = event else {
      return false
    }
    return mouseEvent.isCoalescible
  }
}
