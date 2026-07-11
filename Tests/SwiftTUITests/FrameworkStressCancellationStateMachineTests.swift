import Synchronization
import Testing

@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

private func awaitStressGate(_ gate: OneShotContinuationGate) async {
  await withCheckedContinuation { continuation in
    gate.install(continuation)
  }
}

private final class CancellationStressCounter: Sendable {
  private let value = Mutex(0)
  func increment() { value.withLock { $0 += 1 } }
  var count: Int { value.withLock { $0 } }
}

@Suite("SwiftTUI cancellation state-machine stress behavior", .serialized)
struct FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 001 cancel-before-start is idempotent")
  func cancellationState001CancelBeforeStartIsIdempotent() {
    // Hypothesis: a second cancellation can transition the token away from its terminal state.
    let token = FrameTailJobCancellationToken()
    #expect(token.cancelBeforeStart())
    for _ in 0..<32 {
      #expect(!token.cancelBeforeStart())
      #expect(token.currentState == .cancelledBeforeStart)
    }
  }
}

// NEXT CANCELLATION STRESS TEST
