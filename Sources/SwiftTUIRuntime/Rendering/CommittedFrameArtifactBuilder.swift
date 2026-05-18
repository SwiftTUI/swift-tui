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

  static func frameTailCommitDropBlockers(
    workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  ) -> Set<FrameDropEligibility.Blocker> {
    FrameDropEligibility.frameTailCommitBlockers(
      hasWorkerCustomLayoutCacheUpdates: !workerCustomLayoutCacheUpdates.isEmpty
    )
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
    let dropEligibilityBlockers = frameTailCommitDropBlockers(
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    var diagnostics = FrameDiagnostics.fromCachedPhaseProducts(
      resolved: resolved,
      measured: tail.measured,
      placed: tail.placed,
      semantics: tail.semantics,
      draw: tail.draw,
      invalidatedIdentities: draft.frameContext.invalidatedIdentities,
      resolveWork: draft.resolveContext.resolveWorkTracker?.snapshot,
      layoutWork: tail.diagnostics.layoutWork,
      presentationDamage: tail.presentationDamage,
      presentationSurfaceWidth: tail.raster.size.width,
      phaseTimings: phaseTimings,
      renderGenerations: .init(
        render: draft.renderGeneration,
        layoutInput: tailInputGeneration,
        layoutOutput: layout.generation,
        rasterInput: tailInputGeneration,
        rasterOutput: tail.generation
      ),
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      measurementCache: tail.diagnostics.measurementCache,
      runtimeIssues: runtimeIssues,
      dropEligibilityBlockers: dropEligibilityBlockers
    )
    diagnostics.runtime.registrations = runtimeRegistrationDiagnostics
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

  private static func completedFrameMainActorTimings(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    commitDuration: Duration
  ) -> FrameMainActorTimings {
    let layout = tailOutput.layout
    let tail = tailOutput.tail
    return FrameMainActorTimings(
      blocked: draft.resolveDuration
        + (layout.ranOffMain
          ? .zero : tail.diagnostics.measureDuration + tail.diagnostics.placeDuration)
        + commitDuration,
      suspended: tailOutput.renderSuspensionDuration
    )
  }

  private static func phaseTimings(
    draft: FrameHeadDraft,
    tail: FrameTailOutput,
    commitDuration: Duration
  ) -> FramePhaseTimings {
    FramePhaseTimings(
      resolve: draft.resolveDuration,
      measure: tail.diagnostics.measureDuration,
      place: tail.diagnostics.placeDuration,
      semantics: tail.diagnostics.semanticsDuration,
      draw: tail.diagnostics.drawDuration,
      raster: tail.diagnostics.rasterDuration,
      commit: commitDuration
    )
  }

  @MainActor
  private static func frameHeadDropBlockers(
    _ draft: FrameHeadDraft
  ) -> Set<FrameDropEligibility.Blocker> {
    draft.transaction.draftDropEligibilityBlockers()
  }
}
