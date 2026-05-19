import SwiftTUITestSupport
import Testing

@Suite("AsyncEvent one-shot signal")
struct AsyncEventTests {
  @Test("wait returns immediately when the event already fired")
  func waitAfterFireReturnsImmediately() async {
    let event = AsyncEvent()
    event.fire()
    await event.wait()
  }

  @Test("fire resumes a waiter that suspended first")
  func fireResumesPendingWaiter() async {
    let event = AsyncEvent()
    let waiterStarted = AsyncEvent()

    let waiter = Task {
      waiterStarted.fire()
      await event.wait()
    }

    await waiterStarted.wait()
    event.fire()
    await waiter.value
  }

  @Test("every waiter observes a single firing")
  func allWaitersObserveFiring() async {
    let event = AsyncEvent()
    let waiters = (0..<8).map { _ in
      Task { await event.wait() }
    }

    event.fire()

    for waiter in waiters {
      await waiter.value
    }
  }

  @Test("fire is idempotent and a later wait still returns")
  func fireIsIdempotent() async {
    let event = AsyncEvent()
    event.fire()
    event.fire()
    await event.wait()
  }

  @Test("a cancelled waiter resumes promptly instead of hanging")
  func cancelledWaiterResumes() async {
    let event = AsyncEvent()
    let waiter = Task { await event.wait() }
    waiter.cancel()
    await waiter.value
  }

  @Test("a budgeted wait returns when the event fires inside its budget")
  func budgetedWaitObservesFire() async throws {
    let event = AsyncEvent()
    let clock = ManualStageClock()
    event.fire()
    try await event.wait(
      for: "pre-fired event",
      within: ProgressBudget(stages: 3),
      on: clock
    )
  }

  @Test("a budgeted wait throws once the budget is exhausted")
  func budgetedWaitThrowsWhenExhausted() async {
    let event = AsyncEvent()
    await #expect(throws: StageBudgetExceeded.self) {
      try await event.wait(
        for: "event that never fires",
        within: ProgressBudget(stages: 1),
        on: ExhaustedStageClock()
      )
    }
  }
}
