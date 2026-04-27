import Testing

@testable import Core

@Suite("FrameScheduler intent coalescing")
struct FrameSchedulerIntentCoalescingTests {
  @Test("a freshly consumed frame reports zero coalesced intents when nothing was requested")
  func emptyConsumeReturnsNil() {
    let scheduler = FrameScheduler()
    #expect(scheduler.consumeReadyFrame() == nil)
  }

  @Test("a single request produces an intent count of one")
  func singleRequestCountsAsOne() {
    let scheduler = FrameScheduler()
    scheduler.requestInvalidation(of: [testIdentity("Root")])
    let frame = scheduler.consumeReadyFrame()
    #expect(frame?.intentRequestCount == 1)
  }

  @Test("multiple requests of the same kind merge into one frame and count separately")
  func multipleSameKindRequestsCount() {
    let scheduler = FrameScheduler()
    scheduler.requestInvalidation(of: [testIdentity("A")])
    scheduler.requestInvalidation(of: [testIdentity("B")])
    scheduler.requestInvalidation(of: [testIdentity("C")])
    let frame = scheduler.consumeReadyFrame()
    #expect(frame?.intentRequestCount == 3)
    #expect(frame?.invalidatedIdentities.count == 3)
  }

  @Test("requests of different kinds all increment the same counter")
  func mixedKindRequestsIncrementSameCounter() {
    let scheduler = FrameScheduler()
    scheduler.requestInput()
    scheduler.requestInvalidation(of: [testIdentity("A")])
    scheduler.requestSignal(named: "SIGWINCH")
    scheduler.requestExternalWake(reason: "test")
    scheduler.requestDeadline(.now())
    let frame = scheduler.consumeReadyFrame()
    #expect(frame?.intentRequestCount == 5)
  }

  @Test("the counter resets after every consumeReadyFrame")
  func counterResetsBetweenConsumes() {
    let scheduler = FrameScheduler()
    scheduler.requestInvalidation(of: [testIdentity("A")])
    scheduler.requestInvalidation(of: [testIdentity("B")])
    let first = scheduler.consumeReadyFrame()
    #expect(first?.intentRequestCount == 2)

    scheduler.requestInvalidation(of: [testIdentity("C")])
    let second = scheduler.consumeReadyFrame()
    #expect(second?.intentRequestCount == 1)
  }

  @Test("reset clears the pending intent counter")
  func resetClearsCounter() {
    let scheduler = FrameScheduler()
    scheduler.requestInvalidation(of: [testIdentity("A")])
    scheduler.requestInvalidation(of: [testIdentity("B")])
    scheduler.reset()
    #expect(scheduler.consumeReadyFrame() == nil)

    scheduler.requestInvalidation(of: [testIdentity("C")])
    let frame = scheduler.consumeReadyFrame()
    // After reset, the next consumed frame's count reflects only post-reset
    // requests, not the pre-reset two.
    #expect(frame?.intentRequestCount == 1)
  }

  @Test("a deadline-only frame still surfaces its intent request")
  func deadlineOnlyFrameCountsTheRequest() {
    let scheduler = FrameScheduler()
    scheduler.requestDeadline(.now())
    let frame = scheduler.consumeReadyFrame()
    #expect(frame?.intentRequestCount == 1)
    #expect(frame?.causes.contains(.deadline) == true)
  }

  @Test("animation-aware invalidation requests increment the counter")
  func animationAwareInvalidationCounts() {
    let scheduler = FrameScheduler()
    scheduler.requestInvalidation(
      of: [testIdentity("A")],
      animation: .inherit,
      batchID: nil
    )
    scheduler.requestInvalidation(
      of: [testIdentity("B")],
      animation: .inherit,
      batchID: nil
    )
    let frame = scheduler.consumeReadyFrame()
    #expect(frame?.intentRequestCount == 2)
  }
}
