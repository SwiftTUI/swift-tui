import SwiftTUICore

/// Pure derivation from a raw ``RuntimeFrameSample`` to the rich
/// ``FrameDiagnosticRecord``. This is the formatting/derived-field logic that
/// previously lived in the run loop's record-assembly extensions, lifted to
/// operate on the captured sample alone. It is temporarily in the runtime so
/// the legacy logger keeps working; it moves to `SwiftTUIProfiling` in phase 2.
package enum FrameRecordDerivation {
  package static func record(from sample: RuntimeFrameSample) -> FrameDiagnosticRecord {
    switch sample {
    case .committed(let committed):
      committedRecord(committed)
    case .zeroArtifact(let zero):
      zeroArtifactRecord(zero)
    case .elided(let elided):
      elidedRecord(elided)
    }
  }

  private static func committedRecord(_ sample: CommittedFrameSample) -> FrameDiagnosticRecord {
    let diag = sample.diagnostics
    let publication = diag.runtime.registrations.publication
    let damageDiagnostics = diag.presentation.damage
    let geometryDiagnostics = diag.geometryResolutionDiagnostics
    let cacheMetrics = diag.work.measurementCache
    let cacheHitRate: Double? =
      if let cacheMetrics, cacheMetrics.lookups > 0 {
        Double(cacheMetrics.hits) / Double(cacheMetrics.lookups)
      } else {
        nil
      }
    let pipelineTotal = diag.timing.phaseTimings?.total ?? .zero

    var record = FrameDiagnosticRecord(
      frameNumber: sample.frameNumber,
      causeSummary: causeSummary(for: sample.scheduledFrame),
      focusSyncRerenders: sample.focusSyncRerenders,
      invalidatedIdentityCount: diag.input.invalidatedIdentities.count,
      resolvedNodeCount: diag.counts.resolvedNodes,
      resolvedNodesComputed: diag.work.resolvedNodesComputed,
      resolvedNodesReused: diag.work.resolvedNodesReused,
      measuredNodeCount: diag.counts.measuredNodes,
      measuredNodesComputed: diag.work.measuredNodesComputed,
      measuredNodesReused: diag.work.measuredNodesReused,
      placedNodeCount: diag.counts.placedNodes,
      drawNodeCount: diag.counts.drawNodes,
      interactionRegionCount: diag.counts.interactionRegions,
      focusRegionCount: diag.counts.focusRegions,
      phaseTimings: diag.timing.phaseTimings,
      headTimings: diag.timing.headTimings,
      renderGenerations: diag.timing.renderGenerations,
      desiredGeneration: sample.desiredGeneration,
      coalescedEventBatches: sample.coalescedEventBatches,
      coalescedWakeCauses: formattedWakeCauses(sample.coalescedWakeCauses),
      coalescedIntentRequests: sample.intentRequestCount,
      scheduledAnimationRequest: formattedAnimationRequest(
        sample.scheduledFrame.animationRequest
      ),
      scheduledAnimationBatchID: sample.scheduledFrame.animationBatchID?.value,
      animationControllerActiveAnimationCount: sample.animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: sample.animationControllerHasPendingWork,
      workerTimings: diag.timing.workerTimings,
      mainActorTimings: diag.timing.mainActorTimings,
      customLayoutFallbackCount: diag.work.customLayoutFallbackCount,
      firstCustomLayoutFallbackIdentity: diag.work.firstCustomLayoutFallbackIdentity?.path,
      layoutDependentRealizations: diag.work.layoutDependentRealizations,
      layoutDependentRealizationCacheHits: diag.work.layoutDependentRealizationCacheHits,
      layoutDependentMainActorFallbacks: diag.work.layoutDependentMainActorFallbacks,
      geometryAnchorResolutionMissCount: geometryDiagnostics.anchorResolutionMissCount,
      firstGeometryAnchorResolutionMissIdentity: geometryDiagnostics
        .firstAnchorResolutionMissIdentity?.path,
      geometryMissingNamedCoordinateSpaceCount: geometryDiagnostics
        .missingNamedCoordinateSpaceCount,
      firstGeometryMissingNamedCoordinateSpaceName: geometryDiagnostics
        .firstMissingNamedCoordinateSpaceName,
      geometryDuplicateNamedCoordinateSpaceCount: geometryDiagnostics
        .duplicateNamedCoordinateSpaceCount,
      firstGeometryDuplicateNamedCoordinateSpaceName: geometryDiagnostics
        .firstDuplicateNamedCoordinateSpaceName,
      runtimePointerHandlerCount: diag.runtime.registrations.pointerHandlerCount,
      runtimePointerHoverHandlerCount: diag.runtime.registrations.pointerHoverHandlerCount,
      runtimeGestureRecognizerCount: diag.runtime.registrations.gestureRecognizerCount,
      runtimeGestureStateBindingCount: diag.runtime.registrations.gestureStateBindingCount,
      runtimeIssues: diag.runtime.issues,
      staleFramePolicy: "commit_ordered",
      tailJobState: sample.tailJobState.rawValue,
      tailCancelReason: "-",
      cancelledRenderCount: sample.cancelledRenderCount,
      newestDesiredAtTailStart: sample.desiredGeneration,
      newestDesiredAtTailResult: sample.desiredGeneration,
      dropEligibilityBlockers: sample.dropEligibilityBlockers,
      dropDecision: sample.completedFrameDropDecision?.action.rawValue
        ?? CompletedFrameDropDecision.Action.commitOrdered.rawValue,
      dropGeneration: nil,
      newestDesiredAtDrop: nil,
      dropReconciliationMode: sample.completedFrameDropDecision?.reconciliation.mode
        .rawValue ?? "-",
      dropReconciliationEffects: sample.completedFrameDropDecision?.reconciliation
        .effectSummary ?? "-",
      presentationRecoveryAfterDrop: false,
      inputEventsQueuedDuringRenderSuspension:
        sample.inputEventsQueuedDuringRenderSuspension,
      presentationStrategy: sample.presentationMetrics.strategy == .fullRepaint
        ? "full" : "incremental",
      presentationBytesWritten: sample.presentationMetrics.bytesWritten,
      presentationLinesTouched: sample.presentationMetrics.linesTouched,
      presentationCellsChanged: sample.presentationMetrics.cellsChanged,
      presentationDuration: sample.presentationDuration,
      damageRowCount: damageDiagnostics?.textRowCount,
      damageRangeAwareRowCount: damageDiagnostics?.rangeAwareTextRowCount,
      damageTextSpanCount: damageDiagnostics?.textSpanCount,
      damageTextCellCount: damageDiagnostics?.textCellCount,
      damageGraphicsInvalidationCount: damageDiagnostics?.graphicsInvalidationCount,
      damageRequiresFullTextRepaint: damageDiagnostics?.requiresFullTextRepaint ?? false,
      damageRequiresFullGraphicsReplay: damageDiagnostics?.requiresFullGraphicsReplay
        ?? false,
      presentationUsedSynchronizedOutput: sample.presentationMetrics.usedSynchronizedOutput,
      presentationGraphicsReplayScope: sample.presentationMetrics.graphicsReplayScope.rawValue,
      presentationGraphicsAttachmentsReplayed: sample.presentationMetrics
        .graphicsAttachmentsReplayed,
      presentationEditOperationLowering: sample.presentationMetrics.editOperationLowering
        .rawValue,
      presentationEditOperationCount: sample.presentationMetrics.editOperationCount,
      measurementCacheHitRate: cacheHitRate,
      totalFrameDuration: pipelineTotal + sample.presentationDuration,
      elided: false,
      elidedHeadTotalDuration: nil,
      elidedGraphCheckpointCreateDuration: nil,
      elidedGraphCheckpointRestoreDuration: nil,
      elidedResolveCheckpointRestoreDuration: nil,
      elidedAnimationTickDuration: nil,
      elidedCommitRuntimeRegistrationsDuration: nil,
      elidedAnimationCommitDuration: nil,
      elidedCommitDuration: nil
    )
    record.runtimePublicationMode = publication.publicationMode
    record.runtimeDirtyPlanResult = publication.dirtyPlanResult
    record.runtimePublicationSubtreeRootCount = publication.subtreeRootCount
    record.runtimePublicationRestoredNodeCount = publication.restoredNodeCount
    record.runtimePublicationInvalidatedIdentityCount = publication.invalidatedIdentityCount
    record.runtimePublicationUnmappedInvalidatedIdentityCount =
      publication.unmappedInvalidatedIdentityCount
    record.runtimePublicationUnmappedInvalidatedIdentitySample =
      publication.unmappedInvalidatedIdentitySample
    record.runtimeSelectiveEvaluationDisabledReasons =
      publication.selectiveEvaluationDisabledReasons
    record.runtimePublicationPresentationPortalRootQueued =
      publication.presentationPortalRootQueued
    record.runtimePublicationGraphCheckpointBaselineNodeCount =
      publication.graphCheckpointBaselineNodeCount
    record.runtimePublicationGraphCheckpointPreparedNodeCount =
      publication.graphCheckpointPreparedNodeCount
    record.runtimePublicationGraphCheckpointDirtySubtreeCandidateNodeCount =
      publication.graphCheckpointDirtySubtreeCandidateNodeCount
    record.runtimePublicationGraphCheckpointStrategy =
      publication.graphCheckpointStrategy
    record.runtimePublicationGraphDeltaCheckpointNodeCount =
      publication.graphDeltaCheckpointNodeCount
    record.runtimePublicationGraphDeltaCheckpointCreatedNodeCount =
      publication.graphDeltaCheckpointCreatedNodeCount
    record.runtimePublicationGraphDeltaCheckpointRemovedNodeCount =
      publication.graphDeltaCheckpointRemovedNodeCount
    record.runtimePublicationGraphDeltaCheckpointEpochDelta =
      publication.graphDeltaCheckpointEpochDelta
    record.runtimePublicationGraphCheckpointRestoreStrategy =
      publication.graphCheckpointRestoreStrategy
    record.runtimePublicationGraphCheckpointRestoreFallbackReason =
      publication.graphCheckpointRestoreFallbackReason
    record.runtimePublicationGraphCheckpointDeltaRestoreCount =
      publication.graphCheckpointDeltaRestoreCount
    record.runtimePublicationGraphCheckpointFallbackRestoreCount =
      publication.graphCheckpointFallbackRestoreCount
    record.runtimePublicationNonGraphCheckpointPresent =
      publication.nonGraphCheckpointPresent
    return record
  }

  private static func zeroArtifactRecord(
    _ sample: ZeroArtifactFrameSample
  ) -> FrameDiagnosticRecord {
    FrameDiagnosticRecord(
      frameNumber: sample.frameNumber,
      causeSummary: causeSummary(for: sample.scheduledFrame),
      focusSyncRerenders: 0,
      invalidatedIdentityCount: sample.scheduledFrame.invalidatedIdentities.count,
      resolvedNodeCount: 0,
      resolvedNodesComputed: 0,
      resolvedNodesReused: 0,
      measuredNodeCount: 0,
      measuredNodesComputed: 0,
      measuredNodesReused: 0,
      placedNodeCount: 0,
      drawNodeCount: 0,
      interactionRegionCount: 0,
      focusRegionCount: 0,
      phaseTimings: nil,
      headTimings: nil,
      renderGenerations: .init(render: sample.renderGeneration),
      desiredGeneration: sample.desiredGeneration,
      coalescedEventBatches: sample.coalescedEventBatches,
      coalescedWakeCauses: formattedWakeCauses(sample.coalescedWakeCauses),
      coalescedIntentRequests: sample.intentRequestCount,
      scheduledAnimationRequest: formattedAnimationRequest(
        sample.scheduledFrame.animationRequest
      ),
      scheduledAnimationBatchID: sample.scheduledFrame.animationBatchID?.value,
      animationControllerActiveAnimationCount: sample.animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: sample.animationControllerHasPendingWork,
      workerTimings: nil,
      mainActorTimings: nil,
      customLayoutFallbackCount: 0,
      firstCustomLayoutFallbackIdentity: nil,
      layoutDependentRealizations: 0,
      layoutDependentRealizationCacheHits: 0,
      layoutDependentMainActorFallbacks: 0,
      geometryAnchorResolutionMissCount: 0,
      firstGeometryAnchorResolutionMissIdentity: nil,
      geometryMissingNamedCoordinateSpaceCount: 0,
      firstGeometryMissingNamedCoordinateSpaceName: nil,
      geometryDuplicateNamedCoordinateSpaceCount: 0,
      firstGeometryDuplicateNamedCoordinateSpaceName: nil,
      runtimePointerHandlerCount: 0,
      runtimePointerHoverHandlerCount: 0,
      runtimeGestureRecognizerCount: 0,
      runtimeGestureStateBindingCount: 0,
      runtimeIssues: sample.runtimeIssues,
      staleFramePolicy: sample.staleFramePolicy,
      tailJobState: sample.tailJobState,
      tailCancelReason: sample.tailCancelReason,
      cancelledRenderCount: sample.cancelledRenderCount,
      newestDesiredAtTailStart: sample.desiredGeneration,
      newestDesiredAtTailResult: sample.newestDesiredAtTailResult,
      dropEligibilityBlockers: sample.dropEligibilityBlockers,
      dropDecision: sample.dropDecision,
      dropGeneration: sample.dropGeneration,
      newestDesiredAtDrop: sample.newestDesiredAtDrop,
      dropReconciliationMode: sample.dropReconciliationMode,
      dropReconciliationEffects: sample.dropReconciliationEffects,
      presentationRecoveryAfterDrop: false,
      inputEventsQueuedDuringRenderSuspension:
        sample.inputEventsQueuedDuringRenderSuspension,
      presentationStrategy: "-",
      presentationBytesWritten: 0,
      presentationLinesTouched: 0,
      presentationCellsChanged: 0,
      presentationDuration: .zero,
      damageRowCount: nil,
      damageRangeAwareRowCount: nil,
      damageTextSpanCount: nil,
      damageTextCellCount: nil,
      damageGraphicsInvalidationCount: nil,
      damageRequiresFullTextRepaint: false,
      damageRequiresFullGraphicsReplay: false,
      presentationUsedSynchronizedOutput: false,
      presentationGraphicsReplayScope: "-",
      presentationGraphicsAttachmentsReplayed: 0,
      presentationEditOperationLowering: "-",
      presentationEditOperationCount: 0,
      measurementCacheHitRate: nil,
      totalFrameDuration: .zero,
      elided: false,
      elidedHeadTotalDuration: nil,
      elidedGraphCheckpointCreateDuration: nil,
      elidedGraphCheckpointRestoreDuration: nil,
      elidedResolveCheckpointRestoreDuration: nil,
      elidedAnimationTickDuration: nil,
      elidedCommitRuntimeRegistrationsDuration: nil,
      elidedAnimationCommitDuration: nil,
      elidedCommitDuration: nil
    )
  }

  private static func elidedRecord(
    _ sample: ElidedFrameSample
  ) -> FrameDiagnosticRecord {
    FrameDiagnosticRecord(
      frameNumber: sample.frameNumber,
      causeSummary: causeSummary(for: sample.scheduledFrame),
      focusSyncRerenders: 0,
      invalidatedIdentityCount: sample.scheduledFrame.invalidatedIdentities.count,
      resolvedNodeCount: 0,
      resolvedNodesComputed: 0,
      resolvedNodesReused: 0,
      measuredNodeCount: 0,
      measuredNodesComputed: 0,
      measuredNodesReused: 0,
      placedNodeCount: 0,
      drawNodeCount: 0,
      interactionRegionCount: 0,
      focusRegionCount: 0,
      phaseTimings: nil,
      headTimings: nil,
      renderGenerations: .init(),
      desiredGeneration: sample.desiredGeneration,
      coalescedEventBatches: sample.coalescedEventBatches,
      coalescedWakeCauses: formattedWakeCauses(sample.coalescedWakeCauses),
      coalescedIntentRequests: sample.intentRequestCount,
      scheduledAnimationRequest: formattedAnimationRequest(
        sample.scheduledFrame.animationRequest
      ),
      scheduledAnimationBatchID: sample.scheduledFrame.animationBatchID?.value,
      animationControllerActiveAnimationCount: sample.animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: sample.animationControllerHasPendingWork,
      workerTimings: nil,
      mainActorTimings: nil,
      customLayoutFallbackCount: 0,
      firstCustomLayoutFallbackIdentity: nil,
      layoutDependentRealizations: 0,
      layoutDependentRealizationCacheHits: 0,
      layoutDependentMainActorFallbacks: 0,
      geometryAnchorResolutionMissCount: 0,
      firstGeometryAnchorResolutionMissIdentity: nil,
      geometryMissingNamedCoordinateSpaceCount: 0,
      firstGeometryMissingNamedCoordinateSpaceName: nil,
      geometryDuplicateNamedCoordinateSpaceCount: 0,
      firstGeometryDuplicateNamedCoordinateSpaceName: nil,
      runtimePointerHandlerCount: 0,
      runtimePointerHoverHandlerCount: 0,
      runtimeGestureRecognizerCount: 0,
      runtimeGestureStateBindingCount: 0,
      runtimeIssues: [],
      staleFramePolicy: "elided_offscreen",
      tailJobState: "-",
      tailCancelReason: "-",
      cancelledRenderCount: sample.cancelledRenderCount,
      newestDesiredAtTailStart: sample.desiredGeneration,
      newestDesiredAtTailResult: sample.desiredGeneration,
      dropEligibilityBlockers: [],
      dropDecision: "-",
      dropGeneration: nil,
      newestDesiredAtDrop: nil,
      dropReconciliationMode: "-",
      dropReconciliationEffects: "-",
      presentationRecoveryAfterDrop: false,
      inputEventsQueuedDuringRenderSuspension: 0,
      presentationStrategy: "-",
      presentationBytesWritten: 0,
      presentationLinesTouched: 0,
      presentationCellsChanged: 0,
      presentationDuration: .zero,
      damageRowCount: nil,
      damageRangeAwareRowCount: nil,
      damageTextSpanCount: nil,
      damageTextCellCount: nil,
      damageGraphicsInvalidationCount: nil,
      damageRequiresFullTextRepaint: false,
      damageRequiresFullGraphicsReplay: false,
      presentationUsedSynchronizedOutput: false,
      presentationGraphicsReplayScope: "-",
      presentationGraphicsAttachmentsReplayed: 0,
      presentationEditOperationLowering: "-",
      presentationEditOperationCount: 0,
      measurementCacheHitRate: nil,
      totalFrameDuration: .zero,
      elided: true,
      elidedHeadTotalDuration: sample.timings.headTotal,
      elidedGraphCheckpointCreateDuration: sample.timings.graphCheckpointCreate,
      elidedGraphCheckpointRestoreDuration: sample.timings.graphCheckpointRestore,
      elidedResolveCheckpointRestoreDuration: sample.timings.resolveCheckpointRestore,
      elidedAnimationTickDuration: sample.timings.animationTick,
      elidedCommitRuntimeRegistrationsDuration:
        sample.timings.commitRuntimeRegistrations,
      elidedAnimationCommitDuration: sample.timings.animationCommit,
      elidedCommitDuration: sample.timings.commit
    )
  }

  private static func causeSummary(for scheduledFrame: ScheduledFrame) -> String {
    scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
  }

  private static func formattedWakeCauses(_ causes: Set<WakeCause>) -> String {
    let values = causes.map(\.rawValue).sorted()
    return values.isEmpty ? "-" : values.joined(separator: "+")
  }

  private static func formattedAnimationRequest(_ request: AnimationRequest) -> String {
    switch request {
    case .inherit:
      "inherit"
    case .disabled:
      "disabled"
    case .animate:
      "animate"
    }
  }
}
