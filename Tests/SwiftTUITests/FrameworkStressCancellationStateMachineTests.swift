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

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 002 repeated start preserves started state")
  func cancellationState002RepeatedStartPreservesStartedState() {
    // Hypothesis: repeated start notifications can become false after the first transition.
    let token = FrameTailJobCancellationToken()
    for _ in 0..<32 { #expect(token.markStarted()) }
    #expect(token.currentState.rawValue == "started")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 003 completion before start is inert")
  func cancellationState003CompletionBeforeStartIsInert() {
    // Hypothesis: a premature completion can skip the queued/start arbitration entirely.
    let token = FrameTailJobCancellationToken()
    token.markCompleted()
    #expect(token.currentState.rawValue == "queued")
    #expect(token.markStarted())
    token.markCompleted()
    #expect(token.currentState.rawValue == "completed")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 004 late cancellation cannot undo start")
  func cancellationState004LateCancellationCannotUndoStart() {
    // Hypothesis: cancelBeforeStart can win after markStarted publishes started.
    let token = FrameTailJobCancellationToken()
    #expect(token.markStarted())
    for _ in 0..<32 { #expect(!token.cancelBeforeStart()) }
    #expect(token.currentState.rawValue == "started")
  }
}

extension FrameworkStressCancellationStateMachineTests {
  @Test("stress cancellation state machine 005 start resumes every queued waiter")
  func cancellationState005StartResumesEveryQueuedWaiter() async {
    // Hypothesis: draining the waiter dictionary can omit continuations under fanout.
    let token = FrameTailJobCancellationToken()
    let states = await withTaskGroup(of: String.self, returning: [String].self) { group in
      for _ in 0..<64 {
        group.addTask { await token.waitUntilLeavesQueue().rawValue }
      }
      await Task.yield()
      #expect(token.markStarted())
      var values: [String] = []
      for await value in group { values.append(value) }
      return values
    }
    #expect(states.count == 64)
    #expect(states.allSatisfy { $0 == "started" })
  }
}

// NEXT CANCELLATION STRESS TEST
