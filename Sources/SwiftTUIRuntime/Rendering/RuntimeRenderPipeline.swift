import SwiftTUICore

/// The composed runtime render stages, in canonical execution order.
///
/// This enum is the discriminant the executor switches on: `RuntimeRenderPipeline`
/// iterates `orderedComposition` and dispatches each case through an exhaustive
/// `switch`. Stage order is therefore a structural property of the executor
/// loop — adding, removing, or reordering a case forces the `switch` statements
/// to be updated, so the ordering cannot drift silently (F12).
enum RuntimeRenderStageName: String, CaseIterable, Sendable {
  case head
  case animationInjection
  case latePreferenceReconciliation
  case fusedFrameTail
  case commit

  /// Canonical stage order consumed by every `RuntimeRenderPipeline.render*`
  /// executor loop. `CaseIterable.allCases` already yields declaration order;
  /// this property names that contract explicitly so the executor reads from a
  /// stable, intentional sequence.
  static let orderedComposition: [Self] = allCases
}

struct AsyncFrameTailLayoutStageOutput {
  var frameTailInput: FrameTailInput
  var layout: FrameTailLayoutOutput
  var resolved: ResolvedNode
  var runtimeIssues: [RuntimeIssue]
  var suspensionDuration: Duration
}

struct CancellableFrameTailLayoutStageOutput {
  var layoutStage: AsyncFrameTailLayoutStageOutput
  var cancellationToken: FrameTailJobCancellationToken
}

enum CancellableFrameTailLayoutStageResult {
  case output(CancellableFrameTailLayoutStageOutput)
  case cancelledBeforeStart
}

/// Per-stage handlers for the synchronous one-shot render path, keyed by stage.
///
/// The pipeline executor reads these in `RuntimeRenderStageName.orderedComposition`
/// order; the handler bodies are supplied by the caller.
struct OneShotRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  var latePreferenceReconciliation: (FrameTailInput, ContinuousClock?) -> ReconciledFrameTailLayout
  var fusedFrameTail: (FrameHeadDraft, ReconciledFrameTailLayout) -> FrameTailOutput
  var commit: (FrameHeadDraft, ReconciledFrameTailLayout, FrameTailOutput) -> FrameArtifacts
}

/// Per-stage handlers for the abortable async render path, keyed by stage.
struct AsyncRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  var latePreferenceReconciliation: (FrameHeadDraft) async -> AsyncFrameTailLayoutStageOutput?
  var fusedFrameTail:
    (FrameHeadDraft, AsyncFrameTailLayoutStageOutput) async ->
      AsyncFrameTailDraftOutput
  var commit: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> FrameArtifacts
}

/// Per-stage handlers for the cancellable async render path, keyed by stage.
struct CancellableRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  var latePreferenceReconciliation:
    (FrameHeadDraft) async ->
      CancellableFrameTailLayoutStageResult
  var fusedFrameTail:
    (FrameHeadDraft, CancellableFrameTailLayoutStageOutput) async ->
      AsyncFrameTailDraftOutput
  var cancelledBeforeStart: (FrameHeadDraft) -> CancellableRenderOutcome
  var commitOrDrop: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> CancellableRenderOutcome
}

/// Sequenced executor for the composed runtime render path.
///
/// `RuntimeRenderPipeline` has no configuration: there is no initializer
/// parameter and no stored stage list, so there is no canonical-order
/// `precondition` to guard. Each `render*` entry point walks
/// `RuntimeRenderStageName.orderedComposition` and dispatches every stage
/// through an exhaustive `switch`, invoking the caller-supplied handler for
/// that stage. Stage order is enforced by the executor loop — it is the
/// mechanism, not a comment (F1, F12).
struct RuntimeRenderPipeline: Sendable {
  /// The canonical stage order this executor walks. Exposed so structural
  /// tests can pin that the pipeline runs exactly `orderedComposition`.
  var stageOrder: [RuntimeRenderStageName] {
    RuntimeRenderStageName.orderedComposition
  }

  @MainActor
  func renderOneShot(
    head draft: FrameHeadDraft,
    handlers: OneShotRenderStageHandlers
  ) -> FrameArtifacts {
    var currentDraft = draft
    var reconciledLayout: ReconciledFrameTailLayout?
    var tail: FrameTailOutput?
    var artifacts: FrameArtifacts?

    for stage in RuntimeRenderStageName.orderedComposition {
      switch stage {
      case .head:
        // The frame head is computed by the caller before the executor runs;
        // the executor has nothing to do for this stage.
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
      case .latePreferenceReconciliation:
        reconciledLayout = handlers.latePreferenceReconciliation(
          currentDraft.frameTailInput,
          currentDraft.clock
        )
      case .fusedFrameTail:
        guard let layout = reconciledLayout else {
          preconditionFailure(
            "fusedFrameTail stage ran before latePreferenceReconciliation.")
        }
        tail = handlers.fusedFrameTail(currentDraft, layout)
      case .commit:
        guard let layout = reconciledLayout, let tailOutput = tail else {
          preconditionFailure("commit stage ran before the frame tail completed.")
        }
        artifacts = handlers.commit(currentDraft, layout, tailOutput)
      }
    }

    guard let result = artifacts else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return result
  }

  @MainActor
  func renderAsync(
    head draft: FrameHeadDraft,
    handlers: AsyncRenderStageHandlers
  ) async -> FrameArtifacts {
    var currentDraft = draft
    var layoutStage: AsyncFrameTailLayoutStageOutput?
    var tailOutput: AsyncFrameTailDraftOutput?
    var artifacts: FrameArtifacts?

    for stage in RuntimeRenderStageName.orderedComposition {
      switch stage {
      case .head:
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
      case .latePreferenceReconciliation:
        guard let layout = await handlers.latePreferenceReconciliation(currentDraft) else {
          preconditionFailure("Non-cancellable frame tail unexpectedly cancelled.")
        }
        layoutStage = layout
      case .fusedFrameTail:
        guard let layout = layoutStage else {
          preconditionFailure(
            "fusedFrameTail stage ran before latePreferenceReconciliation.")
        }
        tailOutput = await handlers.fusedFrameTail(currentDraft, layout)
      case .commit:
        guard let tail = tailOutput else {
          preconditionFailure("commit stage ran before the frame tail completed.")
        }
        artifacts = handlers.commit(currentDraft, tail)
      }
    }

    guard let result = artifacts else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return result
  }

  @MainActor
  func renderCancellable(
    head draft: FrameHeadDraft,
    handlers: CancellableRenderStageHandlers
  ) async -> CancellableRenderOutcome {
    var currentDraft = draft
    var layoutStage: CancellableFrameTailLayoutStageOutput?
    var tailOutput: AsyncFrameTailDraftOutput?
    var outcome: CancellableRenderOutcome?

    for stage in RuntimeRenderStageName.orderedComposition {
      // A cancellation observed at the reconciliation stage skips every
      // remaining stage: the loop has already recorded a `cancelledBeforeStart`
      // outcome and the executor stops dispatching work.
      if outcome != nil { break }

      switch stage {
      case .head:
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
      case .latePreferenceReconciliation:
        switch await handlers.latePreferenceReconciliation(currentDraft) {
        case .cancelledBeforeStart:
          outcome = handlers.cancelledBeforeStart(currentDraft)
        case .output(let layout):
          layoutStage = layout
        }
      case .fusedFrameTail:
        guard let layout = layoutStage else {
          preconditionFailure(
            "fusedFrameTail stage ran before latePreferenceReconciliation.")
        }
        tailOutput = await handlers.fusedFrameTail(currentDraft, layout)
      case .commit:
        guard let tail = tailOutput else {
          preconditionFailure("commit stage ran before the frame tail completed.")
        }
        outcome = handlers.commitOrDrop(currentDraft, tail)
      }
    }

    guard let result = outcome else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return result
  }
}
