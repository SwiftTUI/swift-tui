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
    let id: UInt64
    let predicate: () -> Bool
    let continuation: CheckedContinuation<Void, Never>

    init(
      id: UInt64,
      predicate: @escaping () -> Bool,
      continuation: CheckedContinuation<Void, Never>
    ) {
      self.id = id
      self.predicate = predicate
      self.continuation = continuation
    }
  }

  private var waiters: [Waiter] = []
  private var nextID: UInt64 = 0

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
  /// the first `notify()` that makes it true. Also resumes promptly if the
  /// calling task is cancelled, so a cancelled waiter never strands a task
  /// group it is racing inside — `withStageBudget` relies on this.
  package func wait(until predicate: @escaping () -> Bool) async {
    if predicate() {
      return
    }
    let id = nextID
    nextID &+= 1
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if Task.isCancelled {
          continuation.resume()
          return
        }
        waiters.append(
          Waiter(id: id, predicate: predicate, continuation: continuation)
        )
      }
    } onCancel: {
      // `onCancel` runs synchronously on an arbitrary executor; hop back to
      // the MainActor to unregister the waiter and resume it. The hop task is
      // unstructured, so it still runs even though the parent task is cancelled.
      Task { @MainActor in
        guard let index = self.waiters.firstIndex(where: { $0.id == id }) else {
          return
        }
        self.waiters.remove(at: index).continuation.resume()
      }
    }
  }
}
