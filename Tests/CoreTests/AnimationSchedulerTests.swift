import Synchronization
import Testing

@testable import Core

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
}

private struct TestAnimation: Hashable, Sendable {
  let id: String
}
