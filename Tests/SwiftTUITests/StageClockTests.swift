@_spi(Testing) import SwiftTUITestSupport
import Testing

/// A *stage* is one unit of runtime progress (for the run loop, one completed
/// turn). A `ProgressBudget` bounds a wait in stages rather than wall-clock
/// seconds, so the pass/fail criterion is identical on a fast laptop and a
/// starved CI core — only the elapsed time scales with the hardware.
@Suite("Stage clock and progress budget")
struct StageClockTests {
  @Test("ManualStageClock reports the number of stages advanced")
  func manualClockReportsCurrentStage() async {
    let clock = ManualStageClock()
    #expect(await clock.currentStage() == 0)
    clock.advance(by: 3)
    #expect(await clock.currentStage() == 3)
  }

  @Test("waitForStage resumes once the target stage is reached")
  func waitForStageResumesAtTarget() async {
    let clock = ManualStageClock()
    let waiter = Task { await clock.waitForStage(atLeast: 2) }
    clock.advance(by: 2)
    await waiter.value
  }

  @Test("waitForStage returns immediately when the target is already met")
  func waitForStagePastTargetReturnsImmediately() async {
    let clock = ManualStageClock()
    clock.advance(by: 5)
    await clock.waitForStage(atLeast: 3)
  }

  @Test("withStageBudget returns the operation result when it finishes in budget")
  func budgetOperationWins() async throws {
    let clock = ManualStageClock()
    let value = try await withStageBudget(
      "fast operation",
      within: ProgressBudget(stages: 5),
      on: clock
    ) {
      42
    }
    #expect(value == 42)
  }

  @Test("withStageBudget throws StageBudgetExceeded once the budget is exhausted")
  func budgetExceededThrows() async {
    let clock = ManualStageClock()
    let idleClock = ManualStageClock()
    await #expect(throws: StageBudgetExceeded.self) {
      try await withStageBudget(
        "stalled operation",
        within: ProgressBudget(stages: 3),
        on: clock
      ) {
        clock.advance(by: 3)
        await idleClock.waitForStage(atLeast: 1)
      }
    }
  }

  @Test("a cancelled stage waiter resumes promptly instead of hanging")
  func cancelledWaiterResumes() async {
    let clock = ManualStageClock()
    let waiter = Task { await clock.waitForStage(atLeast: 99) }
    waiter.cancel()
    await waiter.value
  }
}
