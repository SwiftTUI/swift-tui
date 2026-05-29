import SwiftTUICore
import SwiftTUIViews

/// Selects execution-strategy-specific work when preparing a frame head.
package enum FrameHeadMode {
  /// Synchronous one-shot render: captures no checkpoints and no worker-safe
  /// indexed-child snapshot, because a one-shot head is never aborted and its
  /// frame tail runs synchronously on the main actor.
  case oneShot
  /// Asynchronous render whose head may be aborted before tail work starts.
  /// Captures the remaining live-state checkpoint bundle and the worker-safe
  /// indexed-child snapshot.
  case abortable
}

/// The non-graph checkpoint bundle captured for an abortable frame head.
///
/// Present only on drafts prepared with `FrameHeadMode.abortable`; a one-shot
/// draft carries `nil`. The graph checkpoint is owned by
/// ``ViewGraphFrameDraft``.
package struct FrameHeadCheckpoints {
  /// Previous-frame selector memory only. Current-frame resolve inputs are
  /// carried by the prepared head and overwritten by the next frame.
  let baselineFrameState: FrameResolveState.Checkpoint
  /// Current-frame input box contents visible to retained evaluator closures.
  let baselineFrameInputs: FrameResolveInputBox.Checkpoint
  /// Prepared selector state captured after resolve, restored only while
  /// previewing or committing this draft.
  let preparedFrameState: FrameResolveState.Checkpoint
  /// Prepared frame input box contents captured after resolve, restored only
  /// while previewing or committing this draft.
  let preparedFrameInputs: FrameResolveInputBox.Checkpoint
}

@MainActor
package final class FrameHeadTransaction {
  package let graphDraft: ViewGraphFrameDraft
  package let registrationDraft: FrameHeadRegistrationDraft
  package let presentationPortalDraft: PresentationPortalDraft
  package let observationDraft: ObservationBridgeDraft?
  package let animationDraft: AnimationFrameDraft
  package let checkpoints: FrameHeadCheckpoints?

  private let viewGraph: ViewGraph
  private let frameState: FrameResolveState
  private let frameInputs: FrameResolveInputBox
  private var didCommit = false
  private var didDiscard = false
  // After the first rollback to baseline, live @State writes may happen while
  // the async tail is still running. Later restores must keep those writes.
  private var hasSuspendedPreparedState = false

  package init(
    viewGraph: ViewGraph,
    frameState: FrameResolveState,
    frameInputs: FrameResolveInputBox,
    graphDraft: ViewGraphFrameDraft,
    registrationDraft: FrameHeadRegistrationDraft,
    presentationPortalDraft: PresentationPortalDraft,
    observationDraft: ObservationBridgeDraft?,
    animationDraft: AnimationFrameDraft,
    checkpoints: FrameHeadCheckpoints?
  ) {
    self.viewGraph = viewGraph
    self.frameState = frameState
    self.frameInputs = frameInputs
    self.graphDraft = graphDraft
    self.registrationDraft = registrationDraft
    self.presentationPortalDraft = presentationPortalDraft
    self.observationDraft = observationDraft
    self.animationDraft = animationDraft
    self.checkpoints = checkpoints
  }

  /// Commits the rendered-frame draft transaction: fires deferred animation
  /// completions, publishes advanced animation/observation/portal/graph state
  /// to live, and returns registration diagnostics.
  ///
  /// - SeeAlso: ``commitElided()`` — an intentionally identical sibling for the
  ///   elision path; keep both in sync until they intentionally diverge.
  package func commit() -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    let diagnostics = graphDraft.commitRuntimeRegistrations(from: viewGraph)
    observationDraft?.commit()
    presentationPortalDraft.commit()
    animationDraft.commit()
    didCommit = true
    return diagnostics
  }

  /// Commits the frame-head draft transaction for an ELIDED frame — fires
  /// deferred animation completions and publishes advanced
  /// animation/observation/portal/graph state to live — WITHOUT a rendering
  /// tail or presentation.
  ///
  /// Commits the same four sub-drafts as ``commit()`` and is byte-identical
  /// to it; the distinct name makes the elision intent explicit and reserves a
  /// future seam. Precondition: the caller must NOT run
  /// finalizeFrame/commitPlanner/present afterward.
  package func commitElided() -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    let diagnostics = graphDraft.commitRuntimeRegistrations(from: viewGraph)
    observationDraft?.commit()
    presentationPortalDraft.commit()
    animationDraft.commit()
    didCommit = true
    return diagnostics
  }

  package func materializePreparedState() {
    precondition(!didCommit && !didDiscard)
    guard let checkpoints else {
      return
    }
    graphDraft.materializePreparedState(
      in: viewGraph,
      preservingCurrentStateMutations: hasSuspendedPreparedState
    )
    observationDraft?.resumeRecording()
    frameState.restoreCheckpoint(checkpoints.preparedFrameState)
    frameInputs.restoreCheckpoint(checkpoints.preparedFrameInputs)
  }

  package func recordPreparedGraphState() {
    precondition(!didCommit && !didDiscard)
    guard checkpoints != nil else {
      return
    }
    graphDraft.recordPreparedCheckpoint(from: viewGraph)
  }

  package func suspendPreparedState() {
    precondition(!didCommit && !didDiscard)
    guard let checkpoints else {
      return
    }
    graphDraft.restoreBaselineState(
      in: viewGraph,
      preservingCurrentStateMutations: hasSuspendedPreparedState
    )
    observationDraft?.suspendRecording()
    frameState.restoreCheckpoint(checkpoints.baselineFrameState)
    frameInputs.restoreCheckpoint(checkpoints.baselineFrameInputs)
    hasSuspendedPreparedState = true
  }

  package func discard() {
    precondition(!didCommit && !didDiscard)
    guard let checkpoints else {
      preconditionFailure(
        "Cannot abort a one-shot frame head — it has no checkpoints."
      )
    }
    registrationDraft.discard()
    graphDraft.discard(
      from: viewGraph,
      preservingCurrentStateMutations: hasSuspendedPreparedState
    )
    presentationPortalDraft.discard()
    observationDraft?.discard()
    animationDraft.discard()
    frameState.restoreCheckpoint(checkpoints.baselineFrameState)
    frameInputs.restoreCheckpoint(checkpoints.baselineFrameInputs)
    didDiscard = true
  }

  package func draftDropEligibilityBlockers() -> Set<FrameDropEligibility.Blocker> {
    registrationDraft.draftDropEligibilityBlockers()
      .union(animationDraft.frameDropEligibilityBlockers)
  }
}

/// Checkpointed main-actor frame head prepared before tail work starts.
///
/// A draft owns preview resolve-side state that can be discarded only if the
/// corresponding tail job is still queued. Once the tail starts, ordered commit
/// decides whether its completed candidate can commit or be dropped.
package struct FrameHeadDraft {
  var clock: ContinuousClock?
  var renderGeneration: RenderGeneration
  var transaction: FrameHeadTransaction
  var resolveContext: ResolveContext
  var graphRootIdentity: Identity
  var frameContext: FrameContext
  var resolved: ResolvedNode
  var frameTailInput: FrameTailInput
  var runtimeIssues: [RuntimeIssue]
  var animationTimestamp: MonotonicInstant
  var resolveDuration: Duration

  var graphDraft: ViewGraphFrameDraft { transaction.graphDraft }
  var registrationDraft: FrameHeadRegistrationDraft { transaction.registrationDraft }
  var presentationPortalDraft: PresentationPortalDraft {
    transaction.presentationPortalDraft
  }
  var observationDraft: ObservationBridgeDraft? { transaction.observationDraft }
  var animationDraft: AnimationFrameDraft { transaction.animationDraft }
  /// The abort checkpoint bundle. `nil` for one-shot heads.
  var checkpoints: FrameHeadCheckpoints? { transaction.checkpoints }
}
