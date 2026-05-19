import Synchronization

/// A one-shot, multi-waiter signal for tests.
///
/// `AsyncEvent` replaces the "set a flag, then poll it under a timeout"
/// anti-pattern. A waiter calls `wait()` and suspends until `fire()` runs;
/// if `fire()` already happened, `wait()` returns immediately. Any number of
/// waiters may observe the same firing.
///
/// Unlike a polling loop, a starved producer never makes a waiter fail — the
/// waiter simply stays suspended until the producer is scheduled. That is the
/// whole point: the test synchronises on the *event*, not on the wall clock.
package final class AsyncEvent: Sendable {
  private struct State {
    var isFired = false
    var waiters: [CheckedContinuation<Void, Never>] = []
  }

  private let state = Mutex(State())

  package init() {}

  /// Signals the event, resuming every pending waiter.
  ///
  /// Idempotent: firing more than once has no additional effect.
  package func fire() {
    let pending: [CheckedContinuation<Void, Never>] = state.withLock { state in
      guard !state.isFired else { return [] }
      state.isFired = true
      defer { state.waiters = [] }
      return state.waiters
    }
    for waiter in pending {
      waiter.resume()
    }
  }

  /// Suspends until `fire()` has been called.
  ///
  /// Returns immediately if the event has already fired.
  package func wait() async {
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
      let alreadyFired = state.withLock { state -> Bool in
        if state.isFired {
          return true
        }
        state.waiters.append(continuation)
        return false
      }
      if alreadyFired {
        continuation.resume()
      }
    }
  }
}
