import Testing

@testable import SwiftTUIGraph

/// Locks the superseded-batch carry (F117): the scheduler's latest-wins
/// animation coalescing keeps ONE batch ID per frame, so a second
/// `withAnimation` before a drain used to silently drop the first batch's
/// ID — and with it the only key that could ever fire that batch's
/// completion. Displaced IDs now ride the frame's
/// `supersededAnimationBatchIDs` so the runtime can park their completions.
@MainActor
@Suite("FrameScheduler superseded animation batches")
struct FrameSchedulerSupersededBatchTests {
  @Test("a coalesced-over batch ID rides the frame as superseded")
  func coalescedOverBatchRidesAsSuperseded() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let batchA = AnimationBatchID(1)
    let batchB = AnimationBatchID(2)

    scheduler.requestInvalidation(
      of: [testIdentity("Root", "A")], animation: .disabled, batchID: batchA
    )
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "B")], animation: .disabled, batchID: batchB
    )

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.animationBatchID == batchB, "latest explicit batch wins the slot")
    #expect(frame?.supersededAnimationBatchIDs == [batchA])

    // The consume drained the superseded list: the next frame starts clean.
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "C")], animation: .disabled, batchID: batchA
    )
    let next = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(next?.supersededAnimationBatchIDs.isEmpty == true)
  }

  @Test("re-requesting the same batch ID does not self-supersede")
  func sameBatchDoesNotSelfSupersede() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let batch = AnimationBatchID(7)

    scheduler.requestInvalidation(
      of: [testIdentity("Root", "A")], animation: .disabled, batchID: batch
    )
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "B")], animation: .disabled, batchID: batch
    )

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.animationBatchID == batch)
    #expect(frame?.supersededAnimationBatchIDs.isEmpty == true)
  }

  @Test("replaying a cancelled frame preserves its batch as superseded when outbid")
  func replayPreservesOutbidBatchAsSuperseded() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let cancelledBatch = AnimationBatchID(11)
    let earlierSuperseded = AnimationBatchID(12)
    let newerBatch = AnimationBatchID(13)

    // A newer explicit batch is already pending when the cancelled frame's
    // intent replays: the cancelled frame's batch must become superseded,
    // not lost, and its own superseded list must merge through.
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "New")], animation: .disabled, batchID: newerBatch
    )
    let cancelled = ScheduledFrame(
      causes: [.invalidation],
      invalidatedIdentities: [testIdentity("Root", "Old")],
      signalNames: [],
      externalReasons: [],
      triggeredDeadline: nil,
      nextDeadline: nil,
      animationRequest: .disabled,
      animationBatchID: cancelledBatch,
      supersededAnimationBatchIDs: [earlierSuperseded]
    )
    scheduler.replayCancelledFrameIntent(cancelled)

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.animationBatchID == newerBatch)
    #expect(frame?.supersededAnimationBatchIDs.contains(cancelledBatch) == true)
    #expect(frame?.supersededAnimationBatchIDs.contains(earlierSuperseded) == true)
  }
}
