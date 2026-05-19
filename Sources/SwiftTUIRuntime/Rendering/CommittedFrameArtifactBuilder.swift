import SwiftTUICore

enum CommittedFrameArtifactBuilder {
  static func workerTimings(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput
  ) -> FrameWorkerTimings? {
    workerTimings(
      tailOutput.tail.diagnostics.workerTimings,
      workerCompletedAt: tailOutput.tail.workerCompletedAt,
      clock: draft.clock
    )
  }

  static func workerTimings(
    draft: FrameHeadDraft,
    tail: FrameTailOutput
  ) -> FrameWorkerTimings? {
    workerTimings(
      tail.diagnostics.workerTimings,
      workerCompletedAt: tail.workerCompletedAt,
      clock: draft.clock
    )
  }

  static func makeOneShotArtifacts(
    draft: FrameHeadDraft,
    reconciledTailLayout: ReconciledFrameTailLayout,
    tail: FrameTailOutput,
    commit: CommitPlan,
    commitDuration: Duration,
    workerTimings: FrameWorkerTimings?,
    runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics
  ) -> FrameArtifacts {
    let phaseTimings = phaseTimings(
      draft: draft,
      tail: tail,
      commitDuration: commitDuration
    )
    return makeArtifacts(
      draft: draft,
      tailInputGeneration: reconciledTailLayout.input.generation,
      layout: reconciledTailLayout.layout,
      resolved: reconciledTailLayout.resolved,
      tail: tail,
      commit: commit,
      phaseTimings: phaseTimings,
      workerTimings: workerTimings,
      mainActorTimings: .init(
        blocked: phaseTimings.total,
        suspended: .zero
      ),
      runtimeIssues: reconciledTailLayout.runtimeIssues,
      runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
    )
  }

  static func makeCompletedFrameArtifacts(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode,
    commit: CommitPlan,
    commitDuration: Duration,
    workerTimings: FrameWorkerTimings?,
    runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics = .init()
  ) -> FrameArtifacts {
    let phaseTimings = phaseTimings(
      draft: draft,
      tail: tailOutput.tail,
      commitDuration: commitDuration
    )
    let mainActorTimings = completedFrameMainActorTimings(
      draft: draft,
      tailOutput: tailOutput,
      commitDuration: commitDuration
    )
    return makeArtifacts(
      draft: draft,
      tailInputGeneration: tailOutput.frameTailInput.generation,
      layout: tailOutput.layout,
      resolved: resolved,
      tail: tailOutput.tail,
      commit: commit,
      phaseTimings: phaseTimings,
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      runtimeIssues: tailOutput.runtimeIssues,
      runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
    )
  }

  @MainActor
  static func eligibility(
    artifacts: FrameArtifacts,
    draft: FrameHeadDraft,
    additionalBlockers: Set<FrameDropEligibility.Blocker>
  ) -> FrameDropEligibility {
    FrameDropEligibility.classify(
      FrameDropEligibility.Candidate(
        artifacts: artifacts,
        additionalBlockers: additionalBlockers.union(
          frameHeadDropBlockers(draft)
        ),
        hasCompleteBarrierSignals: true
      ))
  }

  private static func workerTimings(
    _ workerTimings: FrameWorkerTimings?,
    workerCompletedAt: ContinuousClock.Instant?,
    clock: ContinuousClock?
  ) -> FrameWorkerTimings? {
    var adjustedTimings = workerTimings
    if var timings = adjustedTimings,
      let clock,
      let workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      adjustedTimings = timings
    }
    return adjustedTimings
  }

  private static func makeArtifacts(
    draft: FrameHeadDraft,
    tailInputGeneration: RenderGeneration,
    layout: FrameTailLayoutOutput,
    resolved: ResolvedNode,
    tail: FrameTailOutput,
    commit: CommitPlan,
    phaseTimings: FramePhaseTimings,
    workerTimings: FrameWorkerTimings?,
    mainActorTimings: FrameMainActorTimings,
    runtimeIssues: [RuntimeIssue],
    runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics
  ) -> FrameArtifacts {
    let diagnostics = makeDiagnostics(
      CommittedFrameDiagnosticInput(
        draft: draft,
        tailInputGeneration: tailInputGeneration,
        layout: layout,
        resolved: resolved,
        tail: tail,
        phaseTimings: phaseTimings,
        workerTimings: workerTimings,
        mainActorTimings: mainActorTimings,
        runtimeIssues: runtimeIssues,
        runtimeRegistrationDiagnostics: runtimeRegistrationDiagnostics
      )
    )
    return FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: tail.measured,
      placedTree: tail.placed,
      semanticSnapshot: tail.semantics,
      drawTree: tail.draw,
      rasterSurface: tail.raster,
      presentationDamage: tail.presentationDamage,
      drawnIdentities: tail.drawnIdentities,
      commitPlan: commit,
      diagnostics: diagnostics
    )
  }

  @MainActor
  private static func frameHeadDropBlockers(
    _ draft: FrameHeadDraft
  ) -> Set<FrameDropEligibility.Blocker> {
    draft.transaction.draftDropEligibilityBlockers()
  }
}
