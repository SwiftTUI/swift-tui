import SwiftTUICore

struct CommittedFrameDiagnosticInput {
  var draft: FrameHeadDraft
  var tailInputGeneration: RenderGeneration
  var layout: FrameTailLayoutOutput
  var resolved: ResolvedNode
  var tail: FrameTailOutput
  var phaseTimings: FramePhaseTimings
  var headTimings: FrameHeadTimings
  var workerTimings: FrameWorkerTimings?
  var mainActorTimings: FrameMainActorTimings
  var runtimeIssues: [RuntimeIssue]
  var runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics
}

extension CommittedFrameArtifactBuilder {
  static func makeDiagnostics(
    _ input: CommittedFrameDiagnosticInput
  ) -> FrameDiagnostics {
    let dropEligibilityBlockers = frameTailCommitDropBlockers(
      workerCustomLayoutCacheUpdates: input.layout.workerCustomLayoutCacheUpdates
    )
    var diagnostics = FrameDiagnostics.fromCachedPhaseProducts(
      resolved: input.resolved,
      measured: input.tail.measured,
      placed: input.tail.placed,
      semantics: input.tail.semantics,
      draw: input.tail.draw,
      invalidatedIdentities: input.draft.frameContext.invalidatedIdentities,
      resolveWork: input.draft.resolveContext.resolveWorkTracker?.snapshot,
      layoutWork: input.tail.diagnostics.layoutWork,
      presentationDamage: input.tail.presentationDamage,
      presentationSurfaceWidth: input.tail.raster.size.width,
      phaseTimings: input.phaseTimings,
      headTimings: input.headTimings,
      renderGenerations: .init(
        render: input.draft.renderGeneration,
        layoutInput: input.tailInputGeneration,
        layoutOutput: input.layout.generation,
        rasterInput: input.tailInputGeneration,
        rasterOutput: input.tail.generation
      ),
      workerTimings: input.workerTimings,
      mainActorTimings: input.mainActorTimings,
      measurementCache: input.tail.diagnostics.measurementCache,
      runtimeIssues: input.runtimeIssues,
      dropEligibilityBlockers: dropEligibilityBlockers
    )
    diagnostics.runtime.registrations = input.runtimeRegistrationDiagnostics
    return diagnostics
  }

  static func completedFrameMainActorTimings(
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

  static func phaseTimings(
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

  private static func frameTailCommitDropBlockers(
    workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  ) -> Set<FrameDropEligibility.Blocker> {
    FrameDropEligibility.frameTailCommitBlockers(
      hasWorkerCustomLayoutCacheUpdates: !workerCustomLayoutCacheUpdates.isEmpty
    )
  }
}
