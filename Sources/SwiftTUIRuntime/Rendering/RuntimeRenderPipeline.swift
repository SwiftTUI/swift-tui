import SwiftTUICore

enum RuntimeRenderStageName: String, CaseIterable, Sendable {
  case head
  case animationInjection
  case latePreferenceReconciliation
  case fusedFrameTail
  case commit

  static let orderedComposition: [Self] = [
    .head,
    .animationInjection,
    .latePreferenceReconciliation,
    .fusedFrameTail,
    .commit,
  ]
}

enum FrameHeadDeclaredEffect: String, CaseIterable, Sendable {
  case viewGraph
  case frameState
  case presentationPortalState
  case observationBridge
  case animationController
}

struct FrameHeadDeclaredEffectSet: Equatable, Sendable {
  var effects: Set<FrameHeadDeclaredEffect>

  static let runtimeHead = Self(
    effects: Set(FrameHeadDeclaredEffect.allCases)
  )
}

struct RuntimeFrameHeadStage: Equatable, Sendable {
  var declaredEffects: FrameHeadDeclaredEffectSet
  var isTransactionalWhenAbortable: Bool

  static let defaultRuntimeHead = Self(
    declaredEffects: .runtimeHead,
    isTransactionalWhenAbortable: true
  )
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

struct RuntimeRenderPipeline: Sendable {
  var headStage: RuntimeFrameHeadStage

  var stageOrder: [RuntimeRenderStageName] {
    RuntimeRenderStageName.orderedComposition
  }

  init(
    stageOrder: [RuntimeRenderStageName] = RuntimeRenderStageName.orderedComposition,
    headStage: RuntimeFrameHeadStage = .defaultRuntimeHead
  ) {
    precondition(
      stageOrder == RuntimeRenderStageName.orderedComposition,
      "Runtime render pipeline stage order must stay canonical."
    )
    self.headStage = headStage
  }

  @MainActor
  func renderOneShot(
    head draft: FrameHeadDraft,
    animationInjection: (FrameHeadDraft) -> FrameHeadDraft,
    latePreferenceReconciliation:
      (FrameTailInput, ContinuousClock?) -> ReconciledFrameTailLayout,
    fusedFrameTail: (FrameHeadDraft, ReconciledFrameTailLayout) -> FrameTailOutput,
    commit: (FrameHeadDraft, ReconciledFrameTailLayout, FrameTailOutput) -> FrameArtifacts
  ) -> FrameArtifacts {
    let draft = animationInjection(draft)
    let layout = latePreferenceReconciliation(draft.frameTailInput, draft.clock)
    let tail = fusedFrameTail(draft, layout)
    return commit(draft, layout, tail)
  }

  @MainActor
  func renderAsync(
    head draft: FrameHeadDraft,
    animationInjection: (FrameHeadDraft) -> FrameHeadDraft,
    latePreferenceReconciliation: (FrameHeadDraft) async -> AsyncFrameTailLayoutStageOutput?,
    fusedFrameTail: (FrameHeadDraft, AsyncFrameTailLayoutStageOutput) async ->
      AsyncFrameTailDraftOutput,
    commit: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> FrameArtifacts
  ) async -> FrameArtifacts {
    let draft = animationInjection(draft)
    guard let layout = await latePreferenceReconciliation(draft) else {
      preconditionFailure("Non-cancellable frame tail unexpectedly cancelled.")
    }
    let tailOutput = await fusedFrameTail(draft, layout)
    return commit(draft, tailOutput)
  }

  @MainActor
  func renderCancellable(
    head draft: FrameHeadDraft,
    animationInjection: (FrameHeadDraft) -> FrameHeadDraft,
    latePreferenceReconciliation: (FrameHeadDraft) async ->
      CancellableFrameTailLayoutStageResult,
    fusedFrameTail: (FrameHeadDraft, CancellableFrameTailLayoutStageOutput) async ->
      AsyncFrameTailDraftOutput,
    cancelledBeforeStart: (FrameHeadDraft) -> CancellableRenderOutcome,
    commitOrDrop: (FrameHeadDraft, AsyncFrameTailDraftOutput) -> CancellableRenderOutcome
  ) async -> CancellableRenderOutcome {
    let draft = animationInjection(draft)
    switch await latePreferenceReconciliation(draft) {
    case .cancelledBeforeStart:
      return cancelledBeforeStart(draft)
    case .output(let layout):
      let tailOutput = await fusedFrameTail(draft, layout)
      return commitOrDrop(draft, tailOutput)
    }
  }
}
