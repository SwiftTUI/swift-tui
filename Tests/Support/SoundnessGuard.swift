import SwiftTUICore
package import Testing

/// Attributes process-global soundness-probe growth to the test that produced
/// it.
///
/// D42: probe counters are process-global, so guarded scopes share a
/// process-wide asynchronous exclusion gate and the containing suite must also
/// have `.serialized`. The gate prevents peer suites from overlapping counter
/// windows; the runtime preconditions make the suite-local rollout constraint
/// executable instead of relying on review discipline. The trait is recursive
/// so nested suites inherit the same guard.
package struct FailOnSoundnessViolationGrowth: TestTrait, SuiteTrait, TestScoping {
  package var isRecursive: Bool { true }

  package init() {}

  package func prepare(for test: Test) async throws {
    guard test.isSuite else {
      return
    }
    precondition(
      test.traits.contains { $0 is ParallelizationTrait },
      "FailOnSoundnessViolationGrowth requires a .serialized containing suite"
    )
    await SoundnessCounterScopeGate.shared.registerGuardedSuite(test.id)
  }

  package func provideScope(
    for test: Test,
    testCase _: Test.Case?,
    performing function: @concurrent @Sendable () async throws -> Void
  ) async throws {
    let belongsToGuardedSuite =
      await SoundnessCounterScopeGate.shared.belongsToGuardedSuite(test.id)
    precondition(
      belongsToGuardedSuite,
      """
      FailOnSoundnessViolationGrowth must be installed on a .serialized suite; \
      direct test-function use is unsupported
      """
    )

    await SoundnessCounterScopeGate.shared.acquire()
    let before = await SoundnessCounterSnapshot.current()
    do {
      try await function()
    } catch {
      await recordGrowth(since: before)
      await SoundnessCounterScopeGate.shared.release()
      throw error
    }
    await recordGrowth(since: before)
    await SoundnessCounterScopeGate.shared.release()
  }

  private func recordGrowth(since before: SoundnessCounterSnapshot) async {
    let after = await SoundnessCounterSnapshot.current()
    for growth in after.violationGrowth(since: before) {
      Issue.record(
        """
        soundness counter '\(growth.kind)' grew by \(growth.count): \
        \(growth.detail ?? "no per-kind detail recorded")
        """
      )
    }
  }
}

/// A fair asynchronous mutex for the process-global counter window.
///
/// This is test-support-only state. Keeping it here avoids teaching production
/// probe code about test execution, while ensuring every adoption of
/// ``FailOnSoundnessViolationGrowth`` participates in the same exclusion
/// domain.
package actor SoundnessCounterScopeGate {
  private struct WaitingCountObserver {
    var target: Int
    var continuation: CheckedContinuation<Void, Never>
  }

  static let shared = SoundnessCounterScopeGate()

  private var isHeld = false
  private var waiters: [CheckedContinuation<Void, Never>] = []
  private var waitingCountObservers: [WaitingCountObserver] = []
  private var guardedSuiteIDs: Set<Test.ID> = []

  package init() {}

  package func registerGuardedSuite(_ id: Test.ID) {
    guardedSuiteIDs.insert(id)
  }

  package func belongsToGuardedSuite(_ id: Test.ID) -> Bool {
    var candidate: Test.ID? = id
    while let current = candidate {
      if guardedSuiteIDs.contains(current) {
        return true
      }
      candidate = current.parent
    }
    return false
  }

  package func acquire() async {
    guard isHeld else {
      isHeld = true
      return
    }
    await withCheckedContinuation { continuation in
      waiters.append(continuation)
      resumeSatisfiedWaitingCountObservers()
    }
  }

  package func release() {
    guard !waiters.isEmpty else {
      isHeld = false
      return
    }
    waiters.removeFirst().resume()
  }

  package var waitingCount: Int {
    waiters.count
  }

  /// Test-only synchronization on the lock queue, avoiding sleeps or
  /// scheduler-yield polling in the peer-scope overlap reduction.
  package func waitUntilWaitingCount(atLeast target: Int) async {
    guard waiters.count < target else {
      return
    }
    await withCheckedContinuation { continuation in
      waitingCountObservers.append(
        WaitingCountObserver(target: target, continuation: continuation)
      )
    }
  }

  private func resumeSatisfiedWaitingCountObservers() {
    var remaining: [WaitingCountObserver] = []
    for observer in waitingCountObservers {
      if waiters.count >= observer.target {
        observer.continuation.resume()
      } else {
        remaining.append(observer)
      }
    }
    waitingCountObservers = remaining
  }
}
