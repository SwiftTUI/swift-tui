import Synchronization

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
@_spi(Testing) public final class MainActorConditionSignal {
  /// Set by the cancellation handler, which runs synchronously on the
  /// cancelling executor, so `notify()` stops evaluating a cancelled waiter's
  /// predicate before the MainActor hop that unregisters it has run.
  private final class Cancellation: Sendable {
    private let flag = Atomic(false)

    var isCancelled: Bool {
      flag.load(ordering: .acquiring)
    }

    func cancel() {
      flag.store(true, ordering: .releasing)
    }
  }

  private final class Waiter {
    let id: UInt64
    let predicate: @MainActor () -> Bool
    let cancellation: Cancellation
    let continuation: CheckedContinuation<Void, Never>

    init(
      id: UInt64,
      predicate: @escaping @MainActor () -> Bool,
      cancellation: Cancellation,
      continuation: CheckedContinuation<Void, Never>
    ) {
      self.id = id
      self.predicate = predicate
      self.cancellation = cancellation
      self.continuation = continuation
    }
  }

  private var waiters: [Waiter] = []
  private var nextID: UInt64 = 0

  /// `nonisolated` so a non-`MainActor` owner (such as a test presentation
  /// surface created off the actor) can construct the signal; every *use* of
  /// the signal still happens on the `MainActor`.
  @_spi(Testing) public nonisolated init() {}

  /// Re-evaluates every pending waiter, resuming those whose predicate now holds.
  ///
  /// A waiter whose task has been cancelled is skipped: its predicate never
  /// runs again, and the cancellation hop resumes it.
  ///
  /// Call this after every change to the state the waiters observe.
  @_spi(Testing) public func notify() {
    guard !waiters.isEmpty else {
      return
    }

    var remaining: [Waiter] = []
    var ready: [Waiter] = []
    for waiter in waiters {
      if waiter.cancellation.isCancelled {
        remaining.append(waiter)
      } else if waiter.predicate() {
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
  @_spi(Testing) public func wait(until predicate: @escaping @MainActor () -> Bool) async {
    if predicate() {
      return
    }
    let id = nextID
    nextID &+= 1
    let cancellation = Cancellation()
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        if Task.isCancelled {
          continuation.resume()
          return
        }
        waiters.append(
          Waiter(
            id: id,
            predicate: predicate,
            cancellation: cancellation,
            continuation: continuation
          )
        )
      }
    } onCancel: {
      // `onCancel` runs synchronously on an arbitrary executor. Mark the
      // waiter cancelled right away so `notify()` skips it, then hop back to
      // the MainActor to unregister the waiter and resume it. The hop task is
      // unstructured, so it still runs even though the parent task is cancelled.
      cancellation.cancel()
      Task { @MainActor in
        guard let index = self.waiters.firstIndex(where: { $0.id == id }) else {
          return
        }
        self.waiters.remove(at: index).continuation.resume()
      }
    }
  }
}
