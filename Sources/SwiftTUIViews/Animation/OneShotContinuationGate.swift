import Synchronization

/// Stores a checked continuation until one side wins the race to resume it.
///
/// The "winner" may arrive before the continuation is installed, which lets
/// callers safely bridge cancellation and callback-driven completion without
/// leaking the await when teardown beats registration.
package final class OneShotContinuationGate: Sendable {
  private enum State: Sendable {
    case pending
    case waiting(CheckedContinuation<Void, Never>)
    case resumed
  }

  private let state = Mutex(State.pending)

  package init() {}

  package func install(
    _ continuation: CheckedContinuation<Void, Never>
  ) {
    let continuationToResume = state.withLock { state -> CheckedContinuation<Void, Never>? in
      switch state {
      case .pending:
        state = .waiting(continuation)
        return nil
      case .waiting:
        preconditionFailure("OneShotContinuationGate.install called more than once")
      case .resumed:
        return continuation
      }
    }
    continuationToResume?.resume()
  }

  package func resume() {
    let continuationToResume = state.withLock { state -> CheckedContinuation<Void, Never>? in
      switch state {
      case .pending:
        state = .resumed
        return nil
      case .waiting(let continuation):
        state = .resumed
        return continuation
      case .resumed:
        return nil
      }
    }
    continuationToResume?.resume()
  }
}
