import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

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

  @Test("coalesced invalidations union identities and preserve transaction metadata")
  func coalescedInvalidationsPreserveIdentitiesAndTransactionMetadata() throws {
    let scheduler = FrameScheduler()
    let firstIdentity = testIdentity("Root", "First")
    let secondIdentity = testIdentity("Root", "Second")
    let batchID = AnimationBatchID(42)

    scheduler.requestInvalidation(of: [firstIdentity])
    scheduler.requestInvalidation(
      of: [secondIdentity],
      animation: .disabled,
      batchID: batchID
    )

    let frame = try #require(scheduler.consumeReadyFrame())
    #expect(frame.intentRequestCount == 2)
    #expect(frame.invalidatedIdentities == [firstIdentity, secondIdentity])
    #expect(frame.animationRequest == .disabled)
    #expect(frame.animationBatchID == batchID)
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

  @Test("pending frame waiter wakes for a new request before a future deadline")
  @MainActor
  func pendingFrameWaiterWakesForRequestBeforeFutureDeadline() async {
    let scheduler = FrameScheduler()
    // A far-future deadline: if the waiter completes at all it can only be
    // because the invalidation below woke it, never the deadline. So a plain
    // `await waiter.value` is the whole assertion — a regression hangs and is
    // caught by the CI job timeout, with no wall-clock budget that could
    // flake on a loaded runner.
    scheduler.requestDeadline(.now().advanced(by: .seconds(3600)))

    let waiter = Task { @MainActor in
      await (scheduler as any PendingFrameAwaiting).waitForPendingFrame(at: .now())
    }
    defer {
      waiter.cancel()
    }

    // Give the waiter a turn to reach its suspension point before the
    // invalidation, so this exercises the wake-a-suspended-waiter path.
    // Correctness does not depend on it: a waiter that has not suspended yet
    // simply observes the pending frame immediately instead.
    await Task.yield()
    scheduler.requestInvalidation(of: [testIdentity("EarlyInvalidation")])

    await waiter.value
  }
}
