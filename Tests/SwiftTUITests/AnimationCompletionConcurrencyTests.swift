import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime

/// Deterministic coverage for the async-task animation-registration race that
/// stalled the gallery's PhaseAnimator loop: a `withAnimation { … } completion:`
/// invoked by an async task registers its completion on the LIVE controller
/// between frames. If that registration lands while an earlier frame's tail is
/// in flight, the frame's `publishCommittedState` (a full restore from a draft
/// snapshotted BEFORE the registration) must not clobber it.
@MainActor
struct AnimationCompletionConcurrencyTests {
  @Test("A completion registered on live while a frame draft is in flight survives the commit")
  func concurrentCompletionSurvivesDraftCommit() {
    let controller = AnimationController()

    // Frame N's head transaction begins: its draft snapshots live (no
    // completions yet).
    let draft = controller.makeFrameDraft()

    // An async task (e.g. a PhaseAnimator loop's `advance`) calls
    // `withAnimation … completion:` between frames, registering a completion on
    // the LIVE controller while frame N's tail is still in flight.
    let batchID = AnimationBatchID(424_242)
    controller.registerCompletion(batchID: batchID, closure: {})
    #expect(controller.debugStateSnapshot().completionClosureBatchIDs.contains(batchID))

    // Frame N commits. A full restore from the draft (which predates the
    // registration) would clobber the completion; it must be preserved.
    draft.commit()

    #expect(
      controller.debugStateSnapshot().completionClosureBatchIDs.contains(batchID),
      """
      A withAnimation completion registered on the live controller during an \
      in-flight frame must survive that frame's commit. Losing it orphans the \
      awaiting caller (a PhaseAnimator loop stalls after one phase).
      """
    )
  }

  @Test("A completion the in-flight frame already knew about still drains normally")
  func baselineCompletionStillCommits() {
    let controller = AnimationController()

    // A completion that live already holds when the draft is snapshotted.
    let baselineBatch = AnimationBatchID(111)
    controller.registerCompletion(batchID: baselineBatch, closure: {})

    let draft = controller.makeFrameDraft()
    // A second, concurrent registration after the draft snapshot.
    let concurrentBatch = AnimationBatchID(222)
    controller.registerCompletion(batchID: concurrentBatch, closure: {})

    draft.commit()

    let ids = controller.debugStateSnapshot().completionClosureBatchIDs
    #expect(ids.contains(baselineBatch), "the baseline completion must remain")
    #expect(ids.contains(concurrentBatch), "the concurrent completion must be preserved")
  }
}
