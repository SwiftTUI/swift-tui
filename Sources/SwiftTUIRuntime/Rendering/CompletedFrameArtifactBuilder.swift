import SwiftTUICore

enum CompletedFrameArtifactBuilder {
  static func workerTimings(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput
  ) -> FrameWorkerTimings? {
    var workerTimings = tailOutput.tail.diagnostics.workerTimings
    if var timings = workerTimings,
      let clock = draft.clock,
      let workerCompletedAt = tailOutput.tail.workerCompletedAt
    {
      timings.completionToMainCommit = workerCompletedAt.duration(to: clock.now)
      workerTimings = timings
    }
    return workerTimings
  }

  static func makeArtifacts(
    draft: FrameHeadDraft,
    tailOutput: AsyncFrameTailDraftOutput,
    resolved: ResolvedNode,
    commit: CommitPlan,
    commitDuration: Duration,
    workerTimings: FrameWorkerTimings?,
    runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics = .init()
  ) -> FrameArtifacts {
    let layout = tailOutput.layout
    let tail = tailOutput.tail
    let dropEligibilityBlockers = frameTailCommitDropBlockers(
      workerCustomLayoutCacheUpdates: layout.workerCustomLayoutCacheUpdates
    )
    let phaseTimings = FramePhaseTimings(
      resolve: draft.resolveDuration,
      measure: tail.diagnostics.measureDuration,
      place: tail.diagnostics.placeDuration,
      semantics: tail.diagnostics.semanticsDuration,
      draw: tail.diagnostics.drawDuration,
      raster: tail.diagnostics.rasterDuration,
      commit: commitDuration
    )
    let mainActorTimings = FrameMainActorTimings(
      blocked: draft.resolveDuration
        + (layout.ranOffMain
          ? .zero : tail.diagnostics.measureDuration + tail.diagnostics.placeDuration)
        + commitDuration,
      suspended: tailOutput.renderSuspensionDuration
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
        layoutInput: tailOutput.frameTailInput.generation,
        layoutOutput: layout.generation,
        rasterInput: tailOutput.frameTailInput.generation,
        rasterOutput: tail.generation
      ),
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      measurementCache: tail.diagnostics.measurementCache,
      runtimeIssues: tailOutput.runtimeIssues,
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

  @MainActor
  private static func frameHeadDropBlockers(
    _ draft: FrameHeadDraft
  ) -> Set<FrameDropEligibility.Blocker> {
    draft.transaction.draftDropEligibilityBlockers()
  }
}
