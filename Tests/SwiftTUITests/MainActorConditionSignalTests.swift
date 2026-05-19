@_spi(Testing) import SwiftTUITestSupport
import Testing

@MainActor
@Suite("MainActorConditionSignal poll-free waiter")
struct MainActorConditionSignalTests {
  @Test("wait returns immediately when the predicate already holds")
  func waitReturnsImmediatelyWhenPredicateHolds() async {
    let signal = MainActorConditionSignal()
    await signal.wait(until: { true })
  }

  @Test("notify resumes a waiter once its predicate holds")
  func notifyResumesWaiter() async {
    final class Box {
      var isReady = false
    }
    let box = Box()
    let signal = MainActorConditionSignal()
    let waiter = Task { @MainActor in
      await signal.wait(until: { box.isReady })
    }

    box.isReady = true
    signal.notify()
    await waiter.value
  }

  @Test("a cancelled wait resumes promptly instead of hanging")
  func cancelledWaitResumes() async {
    let signal = MainActorConditionSignal()
    let waiter = Task { @MainActor in
      await signal.wait(until: { false })
    }
    waiter.cancel()
    await waiter.value
  }

  @Test("a budgeted wait throws once the budget is exhausted")
  func budgetedWaitThrowsWhenExhausted() async {
    let signal = MainActorConditionSignal()
    await #expect(throws: StageBudgetExceeded.self) {
      try await signal.wait(
        until: { false },
        for: "predicate that never holds",
        within: ProgressBudget(stages: 1),
        on: ExhaustedStageClock()
      )
    }
  }
}
