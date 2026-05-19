import Synchronization

/// A `Sendable`, poll-free condition waiter for tests.
///
/// `ConditionSignal` is the cross-isolation counterpart of
/// `MainActorConditionSignal`: use it when the observed state lives behind a
/// lock rather than on the `MainActor`. A producer calls `notify()` after each
/// state change; a waiter suspends in `wait(until:)` and is resumed the instant
/// its predicate first holds — re-evaluated only on `notify()`, never on a clock.
///
/// Call `notify()` *outside* any lock the predicate itself acquires, so the two
/// always lock in the order `ConditionSignal` → observed-state.
package final class ConditionSignal: Sendable {
  private struct Waiter {
    let predicate: @Sendable () -> Bool
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct State {
    var waiters: [Waiter] = []
  }

  private let state = Mutex(State())

  package init() {}

  /// Re-evaluates every pending waiter, resuming those whose predicate now holds.
  package func notify() {
    let ready = state.withLock { state -> [CheckedContinuation<Void, Never>] in
      var remaining: [Waiter] = []
      var resumed: [CheckedContinuation<Void, Never>] = []
      for waiter in state.waiters {
        if waiter.predicate() {
          resumed.append(waiter.continuation)
        } else {
          remaining.append(waiter)
        }
      }
      state.waiters = remaining
      return resumed
    }
    for continuation in ready {
      continuation.resume()
    }
  }

  /// Suspends until `predicate` holds.
  ///
  /// Returns immediately if the predicate already holds; otherwise resumes on
  /// the first `notify()` that makes it true.
  package func wait(until predicate: @escaping @Sendable () -> Bool) async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let alreadyHolds = state.withLock { state -> Bool in
        if predicate() {
          return true
        }
        state.waiters.append(Waiter(predicate: predicate, continuation: continuation))
        return false
      }
      if alreadyHolds {
        continuation.resume()
      }
    }
  }
}
