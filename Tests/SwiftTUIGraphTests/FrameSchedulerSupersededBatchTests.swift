import Testing

@testable import SwiftTUIGraph

/// Locks segmented latest-wins animation coalescing (F161): disjoint batches
/// survive together, while a batch whose every claimed identity was displaced
/// rides `supersededAnimationBatchIDs` so the runtime can park its completion.
@MainActor
@Suite("FrameScheduler superseded animation batches")
struct FrameSchedulerSupersededBatchTests {
  @Test("transaction plan selects the most-specific claimed identity")
  func transactionPlanSelectsMostSpecificIdentity() {
    let root = testIdentity("Root")
    let branch = testIdentity("Root", "Branch")
    let leaf = testIdentity("Root", "Branch", "Leaf")
    let request = AnimationRequest.animate(AnyHashableSendable("branch"))
    let plan = FrameAnimationTransactionPlan(
      base: .init(),
      segments: [
        AnimationInvalidationSegment(
          identities: [root],
          animationRequest: .disabled
        ),
        AnimationInvalidationSegment(
          identities: [branch],
          animationRequest: request
        ),
      ]
    )

    #expect(plan.transaction(for: leaf).animationRequest == request)
  }

  @Test("disjoint batch IDs do not supersede each other")
  func disjointBatchesBothRemainLive() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let batchA = AnimationBatchID(100)
    let batchB = AnimationBatchID(101)

    scheduler.requestInvalidation(
      of: [testIdentity("Root", "A")], animation: .disabled, batchID: batchA
    )
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "B")], animation: .disabled, batchID: batchB
    )

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.supersededAnimationBatchIDs.isEmpty == true)
    #expect(frame?.animationSegments.count == 2)
    #expect(frame?.liveAnimationBatchIDs == [batchA, batchB])
  }

  @Test("a fully coalesced-over batch ID rides the frame as superseded")
  func coalescedOverBatchRidesAsSuperseded() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let batchA = AnimationBatchID(1)
    let batchB = AnimationBatchID(2)

    scheduler.requestInvalidation(
      of: [testIdentity("Root", "A")], animation: .disabled, batchID: batchA
    )
    scheduler.requestInvalidation(
      of: [testIdentity("Root", "A")], animation: .disabled, batchID: batchB
    )

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.animationSegments.count == 1)
    #expect(frame?.animationSegments.first?.animationBatchID == batchB)
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
    #expect(frame?.animationSegments.count == 2)
    #expect(frame?.liveAnimationBatchIDs == [batch])
    #expect(frame?.supersededAnimationBatchIDs.isEmpty == true)
  }

  @Test("partial overlap keeps the older batch live on its surviving identity")
  func partialOverlapKeepsOlderBatchLive() throws {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let identityA = testIdentity("Root", "A")
    let identityB = testIdentity("Root", "B")
    let batchA = AnimationBatchID(8)
    let batchB = AnimationBatchID(9)

    scheduler.requestInvalidation(
      of: [identityA, identityB], animation: .disabled, batchID: batchA
    )
    scheduler.requestInvalidation(
      of: [identityA], animation: .disabled, batchID: batchB
    )

    let frame = try #require(
      scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    )
    #expect(frame.animationSegments.count == 2)
    #expect(frame.animationSegments[0].identities == [identityB])
    #expect(frame.animationSegments[0].animationBatchID == batchA)
    #expect(frame.animationSegments[1].identities == [identityA])
    #expect(frame.animationSegments[1].animationBatchID == batchB)
    #expect(frame.supersededAnimationBatchIDs.isEmpty)
  }

  @Test("replaying a cancelled frame preserves its batch as superseded when outbid")
  func replayPreservesOutbidBatchAsSuperseded() {
    let scheduler = FrameScheduler()
    let base = MonotonicInstant(offset: .seconds(60_000))
    let cancelledBatch = AnimationBatchID(11)
    let earlierSuperseded = AnimationBatchID(12)
    let newerBatch = AnimationBatchID(13)

    let contestedIdentity = testIdentity("Root", "Contested")
    // A newer explicit batch is already pending for the same identity when
    // the cancelled frame replays: the cancelled batch must become superseded,
    // not lost, and its own superseded list must merge through.
    scheduler.requestInvalidation(
      of: [contestedIdentity], animation: .disabled, batchID: newerBatch
    )
    let cancelled = ScheduledFrame(
      causes: [.invalidation],
      invalidatedIdentities: [contestedIdentity],
      signalNames: [],
      externalReasons: [],
      triggeredDeadline: nil,
      nextDeadline: nil,
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [contestedIdentity],
          animationRequest: .disabled,
          animationBatchID: cancelledBatch
        )
      ],
      supersededAnimationBatchIDs: [earlierSuperseded]
    )
    scheduler.replayCancelledFrameIntent(cancelled)

    let frame = scheduler.consumeReadyFrame(at: base, armedBefore: scheduler.deadlineArmCut)
    #expect(frame?.animationSegments.first?.animationBatchID == newerBatch)
    #expect(frame?.supersededAnimationBatchIDs.contains(cancelledBatch) == true)
    #expect(frame?.supersededAnimationBatchIDs.contains(earlierSuperseded) == true)
  }

  @Test("focus-rerender identity filtering carries and drops segment metadata together")
  func focusRerenderRewriteKeepsSegmentsAttached() {
    let departing = testIdentity("Root", "Departing")
    let landing = testIdentity("Root", "Landing")
    let inertTrigger = testIdentity("Root", "InertTrigger")
    let liveDepartingTarget = testIdentity("Root", "DepartingHost")
    let liveLandingTarget = testIdentity("Root", "LandingHost")
    let ordinary = testIdentity("Root", "Ordinary")
    let departingBatchID = AnimationBatchID(14)
    let landingBatchID = AnimationBatchID(15)
    let inertBatchID = AnimationBatchID(16)
    var frame = ScheduledFrame(
      causes: [.invalidation],
      invalidatedIdentities: [departing, landing, inertTrigger, ordinary],
      signalNames: [],
      externalReasons: [],
      triggeredDeadline: nil,
      nextDeadline: nil,
      animationSegments: [
        AnimationInvalidationSegment(
          identities: [departing],
          animationRequest: .disabled,
          animationBatchID: departingBatchID
        ),
        AnimationInvalidationSegment(
          identities: [landing],
          animationRequest: .disabled,
          animationBatchID: landingBatchID
        ),
        AnimationInvalidationSegment(
          identities: [inertTrigger],
          animationRequest: .disabled,
          animationBatchID: inertBatchID
        ),
      ]
    )

    frame.rewriteInvalidationIdentities { identities in
      Set(
        identities.compactMap { identity in
          switch identity {
          case departing: liveDepartingTarget
          case landing: liveLandingTarget
          case inertTrigger: nil
          default: identity
          }
        }
      )
    }

    #expect(
      frame.invalidatedIdentities == [liveDepartingTarget, liveLandingTarget, ordinary]
    )
    #expect(
      frame.animationSegments.map(\.identities) == [[liveDepartingTarget], [liveLandingTarget]])
    #expect(frame.liveAnimationBatchIDs == [departingBatchID, landingBatchID])
    #expect(!frame.liveAnimationBatchIDs.contains(inertBatchID))
    #expect(frame.supersededAnimationBatchIDs == [inertBatchID])
  }
}
