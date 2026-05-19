import SwiftTUICore

extension RunLoop {
  @MainActor
  func committedFrameDiagnosticRecord(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    focusSyncRerenders: Int,
    focusGraphChanged: Bool,
    focusBindingChanged: Bool,
    focusedValuesChanged: Bool,
    scrollPositionChanged: Bool,
    preferenceObservationChanged: Bool,
    tailJobState: FrameTailJobState,
    completedFrameDropDecision: CompletedFrameDropDecision?,
    animationControllerHasPendingWork: Bool,
    presentationMetrics: PresentationMetrics,
    presentationDuration: Duration,
    renderedFrames: Int
  ) -> FrameDiagnosticRecord {
    let diag = artifacts.diagnostics
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
    let inputEventsQueuedDuringRenderSuspension =
      renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
    let dropEligibilityBlockers = frameDropEligibilityBlockers(
      artifacts: artifacts,
      scheduledFrame: scheduledFrame,
      focusGraphChanged: focusGraphChanged,
      focusBindingChanged: focusBindingChanged,
      focusedValuesChanged: focusedValuesChanged,
      scrollPositionChanged: scrollPositionChanged,
      preferenceObservationChanged: preferenceObservationChanged,
      diagnosticsRequireFullRecord: true
    )

    return FrameDiagnosticRecord(
      frameNumber: renderedFrames,
      causeSummary: causeSummary(for: scheduledFrame),
      focusSyncRerenders: focusSyncRerenders,
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
      renderGenerations: diag.timing.renderGenerations,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
      coalescedWakeCauses: formattedWakeCauses(
        renderIntentDiagnostics.coalescedWakeCauses
      ),
      coalescedIntentRequests: renderIntentDiagnostics.intentRequestCount,
      scheduledAnimationRequest: formattedAnimationRequest(
        scheduledFrame.animationRequest
      ),
      scheduledAnimationBatchID: scheduledFrame.animationBatchID?.value,
      animationControllerActiveAnimationCount: renderer
        .internalAnimationController.activeAnimationCount,
      animationControllerHasPendingWork: animationControllerHasPendingWork,
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
      tailJobState: tailJobState.rawValue,
      tailCancelReason: "-",
      cancelledRenderCount: cancelledRenderCount,
      newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
      newestDesiredAtTailResult: renderIntentDiagnostics.desiredGeneration,
      dropEligibilityBlockers: dropEligibilityBlockers,
      dropDecision: completedFrameDropDecision?.action.rawValue
        ?? CompletedFrameDropDecision.Action.commitOrdered.rawValue,
      dropGeneration: nil,
      newestDesiredAtDrop: nil,
      dropReconciliationMode: completedFrameDropDecision?.reconciliation.mode
        .rawValue ?? "-",
      dropReconciliationEffects: completedFrameDropDecision?.reconciliation
        .effectSummary ?? "-",
      presentationRecoveryAfterDrop: false,
      inputEventsQueuedDuringRenderSuspension:
        inputEventsQueuedDuringRenderSuspension,
      presentationStrategy: presentationMetrics.strategy == .fullRepaint
        ? "full" : "incremental",
      presentationBytesWritten: presentationMetrics.bytesWritten,
      presentationLinesTouched: presentationMetrics.linesTouched,
      presentationCellsChanged: presentationMetrics.cellsChanged,
      presentationDuration: presentationDuration,
      damageRowCount: damageDiagnostics?.textRowCount,
      damageRangeAwareRowCount: damageDiagnostics?.rangeAwareTextRowCount,
      damageTextSpanCount: damageDiagnostics?.textSpanCount,
      damageTextCellCount: damageDiagnostics?.textCellCount,
      damageGraphicsInvalidationCount: damageDiagnostics?.graphicsInvalidationCount,
      damageRequiresFullTextRepaint: damageDiagnostics?.requiresFullTextRepaint ?? false,
      damageRequiresFullGraphicsReplay: damageDiagnostics?.requiresFullGraphicsReplay
        ?? false,
      presentationUsedSynchronizedOutput: presentationMetrics.usedSynchronizedOutput,
      presentationGraphicsReplayScope: presentationMetrics.graphicsReplayScope.rawValue,
      presentationGraphicsAttachmentsReplayed: presentationMetrics
        .graphicsAttachmentsReplayed,
      presentationEditOperationLowering: presentationMetrics.editOperationLowering.rawValue,
      presentationEditOperationCount: presentationMetrics.editOperationCount,
      measurementCacheHitRate: cacheHitRate,
      totalFrameDuration: pipelineTotal + presentationDuration
    )
  }
}
