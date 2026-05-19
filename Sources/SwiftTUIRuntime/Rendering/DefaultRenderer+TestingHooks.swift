import SwiftTUICore
import SwiftTUIViews

// Test-only entry points into `DefaultRenderer`.
//
// These `package` hooks let the test suite drive individual stages of the
// frame pipeline — preparing a frame head, rendering a tail, previewing or
// committing a completed-frame candidate — so cancellation, drop-eligibility,
// and reconciliation behavior can be exercised in isolation. They carry no
// production call sites; keeping them out of `SwiftTUI.swift` keeps the
// production rendering surface easier to read.
extension DefaultRenderer {
  @MainActor
  package func prepareFrameHeadForCancellationTesting<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameHeadDraft {
    prepareFrameHead(
      root,
      context: context,
      proposal: proposal
    )
  }

  @MainActor
  package func abortPreparedFrameHeadForCancellationTesting(
    _ draft: FrameHeadDraft
  ) {
    abortPreparedFrameHead(draft)
  }

  @MainActor
  package func abortPreparedFrameHead(
    _ draft: FrameHeadDraft
  ) {
    draft.transaction.discard()
  }

  @MainActor
  package func renderPreparedFrameTailForCancellationTesting(
    _ draft: FrameHeadDraft
  ) async {
    _ = await frameTailCoordinator.renderFrameTailDraft(draft)
  }

  @MainActor
  package func discardPreparedFrameTailForReconciliationTesting(
    _ draft: FrameHeadDraft,
    decision: CompletedFrameDropDecision
  ) async -> Bool {
    guard decision.canSkipCompletedFrame else {
      return false
    }

    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    discardCompletedFrameCandidate(
      candidate,
      reconciliation: decision.reconciliation
    )
    return true
  }

  @MainActor
  package func previewCompletedFrameCandidateForTesting(
    _ draft: FrameHeadDraft
  ) async -> CompletedFrameDropDecision {
    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    return candidate.dropDecision
  }

  @MainActor
  package func commitCompletedFrameCandidateForTesting(
    _ draft: FrameHeadDraft
  ) async -> CompletedFrameCandidateCommitPlanComparison {
    let tailOutput = await frameTailCoordinator.renderFrameTailDraft(draft)
    let candidate = makeCompletedFrameCandidate(
      draft: draft,
      tailOutput: tailOutput,
      newestDesiredGeneration: draft.renderGeneration
    )
    let artifacts = commitCompletedFrameCandidate(candidate)
    return CompletedFrameCandidateCommitPlanComparison(
      previewCommit: candidate.previewArtifacts.commitPlan,
      committedCommit: artifacts.commitPlan,
      committedArtifacts: artifacts
    )
  }

  @MainActor
  package func runFrameTailLayoutWorkerJobForCancellationTesting(
    _ operation: @escaping @Sendable () -> Void
  ) async {
    await frameTailRenderer.runLayoutWorkerJobForCancellationTesting(operation)
  }
}
