import Testing

@testable import SwiftTUIGraph

/// Locks the arm-ordinal monotonicity contract the drain-pass cut depends on
/// (F113): `CoalescingState.nextDeadlineArmOrdinal` documents "Never reset — a
/// cut captured before `reset()` must stay meaningful", but nothing enforced
/// it. A refactor that rewound the ordinal on `reset()` would let post-reset
/// re-arms consume against a stale pre-reset cut — reintroducing the F41
/// livelock shape under exactly the slow-runner conditions that took days to
/// diagnose.
@MainActor
@Suite("FrameScheduler arm-ordinal monotonicity")
struct FrameSchedulerArmOrdinalTests {
  @Test("reset() preserves arm-ordinal monotonicity: a pre-reset cut withholds post-reset arms")
  func resetPreservesArmOrdinalMonotonicity() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(50_000))

    scheduler.requestDeadline(base.advanced(by: .milliseconds(10)))
    let preResetCut = scheduler.deadlineArmCut

    scheduler.reset()
    scheduler.requestDeadline(base.advanced(by: .milliseconds(20)))

    // Both deadlines are long due; the post-reset arm must be withheld
    // against the pre-reset cut (its ordinal is NEWER than the cut), while
    // the live view still sees it pending and a fresh cut admits it.
    let now = base.advanced(by: .seconds(10))
    #expect(scheduler.consumeReadyFrame(at: now, armedBefore: preResetCut) == nil)
    #expect(scheduler.hasPendingFrame(at: now))

    let admitted = scheduler.consumeReadyFrame(
      at: now,
      armedBefore: scheduler.deadlineArmCut
    )
    #expect(admitted?.triggeredDeadline == base.advanced(by: .milliseconds(20)))
  }

  @Test("the cut ordinal strictly grows across arms, reset or not")
  func cutOrdinalStrictlyGrowsAcrossArms() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(50_000))

    let initial = scheduler.deadlineArmCut
    scheduler.requestDeadline(base)
    let afterFirstArm = scheduler.deadlineArmCut
    scheduler.reset()
    scheduler.requestDeadline(base.advanced(by: .milliseconds(1)))
    let afterResetAndReArm = scheduler.deadlineArmCut

    #expect(afterFirstArm.rawValue > initial.rawValue)
    #expect(afterResetAndReArm.rawValue > afterFirstArm.rawValue)
  }
}
