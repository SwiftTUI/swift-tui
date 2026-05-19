/// A `MainActor`-isolated, poll-free condition waiter for tests.
///
/// `MainActorConditionSignal` replaces the "poll a predicate on a timer until a
/// timeout" anti-pattern for state that only ever changes on the `MainActor`.
/// A producer calls `notify()` after each state change it owns; a waiter
/// suspends in `wait(until:)` and is resumed the instant its predicate first
/// holds — re-evaluated only on `notify()`, never on a clock.
///
/// Because there is no timeout, a starved producer never makes a waiter *fail*:
/// the waiter simply stays suspended until the producer runs. The test
/// synchronises on the state change, not on the wall clock.
@MainActor
package final class MainActorConditionSignal {
  private final class Waiter {
    let predicate: () -> Bool
    let continuation: CheckedContinuation<Void, Never>

    init(predicate: @escaping () -> Bool, continuation: CheckedContinuation<Void, Never>) {
      self.predicate = predicate
      self.continuation = continuation
    }
  }

  private var waiters: [Waiter] = []

  package init() {}

  /// Re-evaluates every pending waiter, resuming those whose predicate now holds.
  ///
  /// Call this after every change to the state the waiters observe.
  package func notify() {
    guard !waiters.isEmpty else {
      return
    }

    var remaining: [Waiter] = []
    var ready: [Waiter] = []
    for waiter in waiters {
      if waiter.predicate() {
        ready.append(waiter)
      } else {
        remaining.append(waiter)
      }
    }
    waiters = remaining

    for waiter in ready {
      waiter.continuation.resume()
    }
  }

  /// Suspends until `predicate` holds.
  ///
  /// Returns immediately if the predicate already holds; otherwise resumes on
  /// the first `notify()` that makes it true.
  package func wait(until predicate: @escaping () -> Bool) async {
    if predicate() {
      return
    }
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      waiters.append(Waiter(predicate: predicate, continuation: continuation))
    }
  }
}
