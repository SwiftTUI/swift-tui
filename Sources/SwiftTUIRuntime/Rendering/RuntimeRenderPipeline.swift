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

/// Result of a non-cancellable executor that may elide the frame.
///
/// `.rendered` carries the committed artifacts; `.elided` reports that the
/// off-screen elision gate fired right after animation injection — the
/// handler's `elideIfOffscreen` closure has already run the reduced commit
/// (`commitElidedFrame`), so no tail, present, or artifacts are produced.
package enum RenderExecutionResult {
  case rendered(FrameArtifacts)
  case elided
}

/// Result of the cancellable executor that may elide the frame.
///
/// `.rendered` carries the cancellable outcome (committed, cancelled, or
/// dropped); `.elided` reports that the off-screen elision gate fired right
/// after animation injection — see ``RenderExecutionResult``.
package enum CancellableRenderExecutionResult {
  case rendered(CancellableRenderOutcome)
  case elided
}

/// Per-stage handlers for the synchronous one-shot render path, keyed by stage.
///
/// The pipeline executor reads these in `RuntimeRenderStageName.orderedComposition`
/// order; the handler bodies are supplied by the caller.
struct OneShotRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  /// Evaluated immediately after `animationInjection`. Returns `true` once it
  /// has run the reduced commit for an off-screen-only animation tick, telling
  /// the executor to skip the tail, present, and commit stages.
  var elideIfOffscreen: (FrameHeadDraft) -> Bool
  var latePreferenceReconciliation: (FrameTailInput, ContinuousClock?) -> ReconciledFrameTailLayout
  var fusedFrameTail: (FrameHeadDraft, ReconciledFrameTailLayout) -> FrameTailOutput
  var commit: (FrameHeadDraft, ReconciledFrameTailLayout, FrameTailOutput) -> FrameArtifacts
}

/// Per-stage handlers for the abortable async render path, keyed by stage.
struct AsyncRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  /// See ``OneShotRenderStageHandlers/elideIfOffscreen``.
  var elideIfOffscreen: (FrameHeadDraft) -> Bool
  var latePreferenceReconciliation: (FrameHeadDraft) async -> AsyncFrameTailLayoutStageOutput?
  var fusedFrameTail:
    (FrameHeadDraft, AsyncFrameTailLayoutStageOutput) async ->
      AsyncFrameTailDraftOutput
  var commit: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> FrameArtifacts
}

/// Per-stage handlers for the cancellable async render path, keyed by stage.
struct CancellableRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  /// See ``OneShotRenderStageHandlers/elideIfOffscreen``.
  var elideIfOffscreen: (FrameHeadDraft) -> Bool
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
  ) -> RenderExecutionResult {
    var currentDraft = draft
    var reconciledLayout: ReconciledFrameTailLayout?
    var tail: FrameTailOutput?
    var artifacts: FrameArtifacts?
    var elided = false

    for stage in RuntimeRenderStageName.orderedComposition {
      // Off-screen elision fires immediately after animation injection: once
      // the gate has run the reduced commit, every remaining stage (tail,
      // present, commit) is skipped.
      if elided { break }

      switch stage {
      case .head:
        // The frame head is computed by the caller before the executor runs;
        // the executor has nothing to do for this stage.
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
        elided = handlers.elideIfOffscreen(currentDraft)
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

    if elided {
      return .elided
    }
    guard let result = artifacts else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return .rendered(result)
  }

  @MainActor
  func renderAsync(
    head draft: FrameHeadDraft,
    handlers: AsyncRenderStageHandlers
  ) async -> RenderExecutionResult {
    var currentDraft = draft
    var layoutStage: AsyncFrameTailLayoutStageOutput?
    var tailOutput: AsyncFrameTailDraftOutput?
    var artifacts: FrameArtifacts?
    var elided = false

    for stage in RuntimeRenderStageName.orderedComposition {
      if elided { break }

      switch stage {
      case .head:
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
        elided = handlers.elideIfOffscreen(currentDraft)
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

    if elided {
      return .elided
    }
    guard let result = artifacts else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return .rendered(result)
  }

  @MainActor
  func renderCancellable(
    head draft: FrameHeadDraft,
    handlers: CancellableRenderStageHandlers
  ) async -> CancellableRenderExecutionResult {
    var currentDraft = draft
    var layoutStage: CancellableFrameTailLayoutStageOutput?
    var tailOutput: AsyncFrameTailDraftOutput?
    var outcome: CancellableRenderOutcome?
    var elided = false

    for stage in RuntimeRenderStageName.orderedComposition {
      // A cancellation observed at the reconciliation stage, or an off-screen
      // elision observed after animation injection, skips every remaining
      // stage: the loop stops dispatching work once either is recorded.
      if outcome != nil || elided { break }

      switch stage {
      case .head:
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
        elided = handlers.elideIfOffscreen(currentDraft)
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

    if elided {
      return .elided
    }
    guard let result = outcome else {
      preconditionFailure("Render pipeline finished without a commit stage.")
    }
    return .rendered(result)
  }
}
