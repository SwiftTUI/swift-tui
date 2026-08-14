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

/// What the reconciliation stage produced.
///
/// `.layout` continues into the frame tail. `.finished` ends the frame there,
/// before the tail starts — the cancellable path's cancelled-before-start leg.
/// A path that cannot be cancelled simply never returns `.finished`, which is
/// how one executor serves both without a cancellation-shaped special case.
enum ReconciledLayoutStage<Layout, Outcome> {
  case layout(Layout)
  case finished(Outcome)
}

/// Result of an executor that may elide the frame.
///
/// `.rendered` carries whatever the path's commit stage produced; `.elided`
/// reports that the off-screen elision gate fired right after animation
/// injection — the handler's `commitElidedFrameIfOffscreen` closure has already
/// run the reduced commit (`commitElidedFrame`), so no tail, present, or
/// artifacts are produced.
package enum RenderExecutionOutcome<Outcome> {
  case rendered(Outcome)
  case elided
}

/// The non-cancellable paths commit artifacts directly.
package typealias RenderExecutionResult = RenderExecutionOutcome<FrameArtifacts>

/// The cancellable path commits an outcome that may instead be cancelled or
/// dropped.
package typealias CancellableRenderExecutionResult =
  RenderExecutionOutcome<CancellableRenderOutcome>

/// Per-stage handlers for the synchronous one-shot render path, keyed by stage.
///
/// The pipeline executor reads these in `RuntimeRenderStageName.orderedComposition`
/// order; the handler bodies are supplied by the caller.
struct OneShotRenderStageHandlers {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  /// Evaluated immediately after `animationInjection`. Returns `true` once it
  /// has run the reduced commit for an off-screen-only animation tick, telling
  /// the executor to skip the tail, present, and commit stages.
  var commitElidedFrameIfOffscreen: (FrameHeadDraft) -> Bool
  var latePreferenceReconciliation: (FrameHeadDraft) -> ReconciledFrameTailLayout
  var fusedFrameTail: (FrameHeadDraft, ReconciledFrameTailLayout) -> FrameTailOutput
  var commit: (FrameHeadDraft, ReconciledFrameTailLayout, FrameTailOutput) -> FrameArtifacts
}

/// Per-stage handlers for an asynchronous render path, keyed by stage.
///
/// `Layout` is what this path's reconciliation stage hands to its frame tail,
/// and `Outcome` is what its commit stage produces. The abortable path uses
/// (`AsyncFrameTailLayoutStageOutput`, `FrameArtifacts`); the cancellable path
/// carries a cancellation token in its layout and may commit *or drop*, so it
/// uses (`CancellableFrameTailLayoutStageOutput`, `CancellableRenderOutcome`).
///
/// Those two axes were the whole difference between the former `renderAsync`
/// and `renderCancellable` executors — everything else about the walk was
/// duplicated, including the stage-order loop and its precondition messages.
struct AsyncRenderStageHandlers<Layout, Outcome> {
  var animationInjection: (FrameHeadDraft) -> FrameHeadDraft
  /// See ``OneShotRenderStageHandlers/commitElidedFrameIfOffscreen``.
  var commitElidedFrameIfOffscreen: (FrameHeadDraft) -> Bool
  /// Produces the layout for the tail, or finishes the frame before it starts.
  ///
  /// A path with no cancellation returns `.layout` unconditionally; where the
  /// former executor asserted "non-cancellable frame unexpectedly cancelled",
  /// that claim now lives in the handler that actually knows it holds.
  var latePreferenceReconciliation: (FrameHeadDraft) async -> ReconciledLayoutStage<Layout, Outcome>
  var fusedFrameTail: (FrameHeadDraft, Layout) async -> AsyncFrameTailDraftOutput
  var commit: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> Outcome
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
        elided = handlers.commitElidedFrameIfOffscreen(currentDraft)
      case .latePreferenceReconciliation:
        reconciledLayout = handlers.latePreferenceReconciliation(currentDraft)
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

  /// The asynchronous executor, shared by the abortable and cancellable paths.
  ///
  /// The two differ only in what their stages carry — see
  /// ``AsyncRenderStageHandlers`` — so the walk itself, its early-exit rule,
  /// and its precondition vocabulary exist once.
  @MainActor
  func renderAsync<Layout, Outcome>(
    head draft: FrameHeadDraft,
    handlers: AsyncRenderStageHandlers<Layout, Outcome>
  ) async -> RenderExecutionOutcome<Outcome> {
    var currentDraft = draft
    var layoutStage: Layout?
    var tailOutput: AsyncFrameTailDraftOutput?
    var outcome: Outcome?
    var elided = false

    for stage in RuntimeRenderStageName.orderedComposition {
      // A frame finished at the reconciliation stage (cancellation), or an
      // off-screen elision observed after animation injection, skips every
      // remaining stage: the loop stops dispatching work once either is
      // recorded. A path that cannot be cancelled only ever records an outcome
      // at `.commit`, the last stage, so the first disjunct is vacuous there.
      if outcome != nil || elided { break }

      switch stage {
      case .head:
        break
      case .animationInjection:
        currentDraft = handlers.animationInjection(currentDraft)
        elided = handlers.commitElidedFrameIfOffscreen(currentDraft)
      case .latePreferenceReconciliation:
        switch await handlers.latePreferenceReconciliation(currentDraft) {
        case .finished(let finished):
          outcome = finished
        case .layout(let layout):
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
        outcome = handlers.commit(currentDraft, tail)
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
