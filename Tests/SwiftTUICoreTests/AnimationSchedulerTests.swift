import Synchronization
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Animation scheduler plumbing")
struct AnimationSchedulerTests {
  @Test("requestDeadline fires the wake handler")
  func requestDeadlineFiresWakeHandler() throws {
    let scheduler = FrameScheduler()
    let wakeCount = Mutex<Int>(0)
    scheduler.setWakeHandler {
      wakeCount.withLock { $0 += 1 }
    }

    scheduler.requestDeadline(.now().advanced(by: .milliseconds(100)))

    #expect(wakeCount.withLock { $0 } == 1, "requestDeadline should fire the wake handler")
  }

  @Test("coalesced earlier deadline fires wake handler again")
  func coalescedEarlierDeadlineWakes() throws {
    let scheduler = FrameScheduler()
    let wakeCount = Mutex<Int>(0)
    scheduler.setWakeHandler {
      wakeCount.withLock { $0 += 1 }
    }

    let now = MonotonicInstant.now()
    scheduler.requestDeadline(now.advanced(by: .milliseconds(500)))
    scheduler.requestDeadline(now.advanced(by: .milliseconds(100)))

    #expect(wakeCount.withLock { $0 } == 2)
  }

  @Test("animation request propagates through invalidation")
  func animationAwareInvalidationPropagates() throws {
    let scheduler = FrameScheduler()
    let animationRequest = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "fast"))
    )
    scheduler.requestInvalidation(
      of: [Identity(components: [] as [IdentityComponent])],
      animation: animationRequest
    )

    let frame = scheduler.consumeReadyFrame(at: .now())
    #expect(frame?.animationRequest == animationRequest)
  }

  @Test("consumed frame resets pending animation request to inherit")
  func consumedFrameResetsAnimationRequest() throws {
    let scheduler = FrameScheduler()
    let animationRequest = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "fast"))
    )
    scheduler.requestInvalidation(
      of: [Identity(components: [] as [IdentityComponent])],
      animation: animationRequest
    )
    _ = scheduler.consumeReadyFrame(at: .now())

    // After consumption, a plain invalidation should not carry animation.
    scheduler.requestInvalidation(of: [Identity(components: [] as [IdentityComponent])])
    let nextFrame = scheduler.consumeReadyFrame(at: .now())
    #expect(nextFrame?.animationRequest == .inherit)
  }

  @Test("explicit animation request beats inherit during coalescing")
  func explicitAnimationBeatsInheritDuringCoalescing() throws {
    let scheduler = FrameScheduler()

    // First: plain invalidation (inherit)
    scheduler.requestInvalidation(of: [Identity(components: [] as [IdentityComponent])])

    // Then: explicit animation request
    let explicit = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "explicit"))
    )
    scheduler.requestInvalidation(
      of: [Identity(components: [] as [IdentityComponent])],
      animation: explicit
    )

    let frame = scheduler.consumeReadyFrame(at: .now())
    #expect(frame?.animationRequest == explicit)
  }

  @Test("replaying a cancelled animation frame restores its transaction onto pending work")
  func replayCancelledAnimationFrameRestoresTransaction() throws {
    let scheduler = FrameScheduler()
    let animatedIdentity = testIdentity("Root", "Animated")
    let newerIdentity = testIdentity("Root", "Newer")
    let animationRequest = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "cancelled"))
    )
    let batchID = AnimationBatchID(1)

    scheduler.requestInvalidation(
      of: [animatedIdentity],
      animation: animationRequest,
      batchID: batchID
    )
    let cancelledFrame = try #require(scheduler.consumeReadyFrame(at: .now()))

    scheduler.requestInvalidation(of: [newerIdentity])
    scheduler.replayCancelledFrameIntent(cancelledFrame)

    let replayedFrame = try #require(scheduler.consumeReadyFrame(at: .now()))
    #expect(replayedFrame.causes == [.invalidation])
    #expect(
      replayedFrame.invalidatedIdentities == Set([animatedIdentity, newerIdentity])
    )
    #expect(replayedFrame.animationRequest == animationRequest)
    #expect(replayedFrame.animationBatchID == batchID)
    #expect(replayedFrame.intentRequestCount == 2)
  }

  @Test("replaying a cancelled animation frame does not replace newer explicit animation")
  func replayCancelledAnimationFrameKeepsNewerExplicitAnimation() throws {
    let scheduler = FrameScheduler()
    let cancelledIdentity = testIdentity("Root", "Cancelled")
    let newerIdentity = testIdentity("Root", "Newer")
    let cancelledAnimation = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "cancelled"))
    )
    let newerAnimation = AnimationRequest.animate(
      AnimationBox(TestAnimation(id: "newer"))
    )
    let cancelledBatchID = AnimationBatchID(1)
    let newerBatchID = AnimationBatchID(2)

    scheduler.requestInvalidation(
      of: [cancelledIdentity],
      animation: cancelledAnimation,
      batchID: cancelledBatchID
    )
    let cancelledFrame = try #require(scheduler.consumeReadyFrame(at: .now()))

    scheduler.requestInvalidation(
      of: [newerIdentity],
      animation: newerAnimation,
      batchID: newerBatchID
    )
    scheduler.replayCancelledFrameIntent(cancelledFrame)

    let replayedFrame = try #require(scheduler.consumeReadyFrame(at: .now()))
    #expect(
      replayedFrame.invalidatedIdentities == Set([cancelledIdentity, newerIdentity])
    )
    #expect(replayedFrame.animationRequest == newerAnimation)
    #expect(replayedFrame.animationBatchID == newerBatchID)
  }

  @Test("replaying a cancelled input-only frame does not synthesize invalidation")
  func replayCancelledInputOnlyFrameDoesNotSynthesizeInvalidation() throws {
    let scheduler = FrameScheduler()
    scheduler.requestInput()
    let cancelledFrame = try #require(scheduler.consumeReadyFrame(at: .now()))

    scheduler.replayCancelledFrameIntent(cancelledFrame)

    #expect(scheduler.consumeReadyFrame(at: .now()) == nil)
  }
}

private struct TestAnimation: Hashable, Sendable {
  let id: String
}
