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
@_spi(Testing) public final class AsyncEvent: Sendable {
  private struct Waiter {
    let id: UInt64
    let continuation: CheckedContinuation<Void, Never>
  }

  private struct State {
    var isFired = false
    var nextID: UInt64 = 0
    var waiters: [Waiter] = []
  }

  private let state = Mutex(State())

  @_spi(Testing) public init() {}

  /// Signals the event, resuming every pending waiter.
  ///
  /// Idempotent: firing more than once has no additional effect.
  @_spi(Testing) public func fire() {
    let pending: [CheckedContinuation<Void, Never>] = state.withLock { state in
      guard !state.isFired else { return [] }
      state.isFired = true
      defer { state.waiters = [] }
      return state.waiters.map(\.continuation)
    }
    for continuation in pending {
      continuation.resume()
    }
  }

  /// Suspends until `fire()` has been called.
  ///
  /// Returns immediately if the event has already fired. Resumes promptly if
  /// the calling task is cancelled, so a cancelled waiter never strands a
  /// task group it is racing inside.
  @_spi(Testing) public func wait() async {
    let id = state.withLock { state -> UInt64 in
      let id = state.nextID
      state.nextID &+= 1
      return id
    }
    await withTaskCancellationHandler {
      await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        let resumeImmediately = state.withLock { state -> Bool in
          if state.isFired || Task.isCancelled {
            return true
          }
          state.waiters.append(Waiter(id: id, continuation: continuation))
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
