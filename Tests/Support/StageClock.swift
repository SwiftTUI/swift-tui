import Synchronization

/// A deterministic, clock-independent source of progress "stages" for tests.
///
/// A *stage* is one unit of runtime progress — for the run loop, one completed
/// turn (see the `.turnCompleted` progress event). Stage budgets relate to
/// wall-clock time on any single machine — one stage costs roughly one turn's
/// work — but the pass/fail criterion is the *count*, so a budget never fails
/// spuriously just because a shared CI core was starved. The same budget that
/// finishes in 6 s on a laptop finishes in 30 s on a slow runner, and passes
/// on both.
package protocol StageClock: Sendable {
  /// The number of stages elapsed so far.
  func currentStage() async -> Int

  /// Suspends until `currentStage()` has reached `target`.
  ///
  /// Returns immediately if the target has already been reached. Resumes
  /// promptly if the calling task is cancelled, so it is safe to race inside
  /// a task group.
  func waitForStage(atLeast target: Int) async
}

/// A bound, denominated in stages, on how long a test will wait for an event.
package struct ProgressBudget: Sendable {
  /// The maximum number of stages the wait may span before it is abandoned.
  package var stages: Int

  package init(stages: Int) {
    precondition(stages >= 1, "A progress budget must allow at least one stage.")
    self.stages = stages
  }
}

/// Thrown by `withStageBudget` when a budget elapses before its operation
/// finishes — the deterministic, hardware-independent replacement for a
/// wall-clock timeout.
package struct StageBudgetExceeded: Error, CustomStringConvertible, Sendable {
  package let label: String
  package let stages: Int

  package init(label: String, stages: Int) {
    self.label = label
    self.stages = stages
  }

  package var description: String {
    "Waiting for \(label) exceeded its budget of \(stages) runtime stage(s)."
  }
}

/// Runs `operation`, abandoning it with `StageBudgetExceeded` if `budget`
/// stages of `clock` elapse before it finishes.
///
/// `operation` must be cancellation-aware: when the budget wins the race the
/// operation task is cancelled, and the enclosing task group waits for it to
/// unwind before this function returns.
package func withStageBudget<R: Sendable>(
  _ label: String,
  within budget: ProgressBudget,
  on clock: some StageClock,
  _ operation: @escaping @Sendable () async -> R
) async throws -> R {
  let deadline = await clock.currentStage() + budget.stages
  return try await withThrowingTaskGroup(of: R.self) { group in
    group.addTask {
      await operation()
    }
    group.addTask {
      await clock.waitForStage(atLeast: deadline)
      throw StageBudgetExceeded(label: label, stages: budget.stages)
    }
    defer { group.cancelAll() }
    guard let result = try await group.next() else {
      throw StageBudgetExceeded(label: label, stages: budget.stages)
    }
    return result
  }
}

/// A `StageClock` that treats every stage as already elapsed: any budget
/// checked against it is exhausted immediately.
///
/// Use it to exercise budget-exceeded paths deterministically, without having
/// to race a real clock past its deadline.
package struct ExhaustedStageClock: StageClock {
  package init() {}

  package func currentStage() async -> Int {
    0
  }

  package func waitForStage(atLeast target: Int) async {}
}

/// A `StageClock` whose stages are advanced explicitly by the test.
///
/// Use it to unit-test budget logic without a running runtime, or as a
/// stand-in progress source the test drives by hand.
package final class ManualStageClock: StageClock {
  private struct Waiter {
    let id: UInt64
    let target: Int
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct State {
    var elapsed = 0
    var nextID: UInt64 = 0
    var waiters: [Waiter] = []
  }

  private let state = Mutex(State())

  package init() {}

  /// Advances the clock by `count` stages, resuming every waiter whose target
  /// has now been reached.
  package func advance(by count: Int = 1) {
    precondition(count >= 0, "Cannot advance a stage clock backwards.")
    let resumed: [CheckedContinuation<Void, Never>] = state.withLock { state in
      state.elapsed += count
      let ready = state.waiters.filter { $0.target <= state.elapsed }
      state.waiters.removeAll { $0.target <= state.elapsed }
      return ready.map(\.continuation)
    }
    for continuation in resumed {
      continuation.resume()
    }
  }

  package func currentStage() async -> Int {
    state.withLock { $0.elapsed }
  }

  package func waitForStage(atLeast target: Int) async {
    let id = state.withLock { state -> UInt64 in
      let id = state.nextID
      state.nextID &+= 1
      return id
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeImmediately = state.withLock { state -> Bool in
          if state.elapsed >= target || Task.isCancelled {
            return true
          }
          state.waiters.append(
            Waiter(id: id, target: target, continuation: continuation)
          )
          return false
        }
        if resumeImmediately {
          continuation.resume()
        }
      }
    } onCancel: {
      let continuation = state.withLock { state -> CheckedContinuation<Void, Never>? in
        guard let index = state.waiters.firstIndex(where: { $0.id == id }) else {
          return nil
        }
        return state.waiters.remove(at: index).continuation
      }
      continuation?.resume()
    }
  }
}
