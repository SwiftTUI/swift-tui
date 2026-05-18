import SwiftTUICore

extension RunLoop {
  @MainActor
  func logCommittedFrameDiagnostics(
    diagnosticsLogger: FrameDiagnosticsLogger?,
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
  ) {
    guard let diagnosticsLogger else {
      return
    }

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

    diagnosticsLogger.log(
      FrameDiagnosticRecord(
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
    )
  }

  @MainActor
  func logCancelledFrameTail(
    diagnosticsLogger: FrameDiagnosticsLogger?,
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
    runtimeIssues: [RuntimeIssue],
    tailJobState: FrameTailJobState,
    tailCancelReason: String,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool
  ) {
    guard let diagnosticsLogger else {
      return
    }
    diagnosticsLogger.log(
      zeroArtifactRecord(
        frameNumber: renderedFrames + 1,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderGeneration,
        runtimeIssues: runtimeIssues,
        staleFramePolicy: "cancel_pending_before_start",
        tailJobState: tailJobState.rawValue,
        tailCancelReason: tailCancelReason,
        newestDesiredAtTailResult: nextRenderIntentGeneration,
        animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
        animationControllerHasPendingWork: animationControllerHasPendingWork,
        dropEligibilityBlockers: [],
        dropDecision: "-",
        dropGeneration: nil,
        newestDesiredAtDrop: nil,
        dropReconciliationMode: "-",
        dropReconciliationEffects: "-"
      )
    )
  }

  @MainActor
  func logDroppedCompletedFrame(
    diagnosticsLogger: FrameDiagnosticsLogger?,
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
    newestDesiredGeneration: RenderGeneration,
    decision: CompletedFrameDropDecision?,
    runtimeIssues: [RuntimeIssue],
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool
  ) {
    guard let diagnosticsLogger else {
      return
    }
    let reconciliation =
      decision?.reconciliation
      ?? .blocked(
        reason: .dropEligibilityBlockers
      )
    diagnosticsLogger.log(
      zeroArtifactRecord(
        frameNumber: renderedFrames + 1,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderGeneration,
        runtimeIssues: runtimeIssues,
        staleFramePolicy: "drop_completed_visual_only",
        tailJobState: FrameTailJobState.droppedCompleted.rawValue,
        tailCancelReason: "-",
        newestDesiredAtTailResult: newestDesiredGeneration.rawValue,
        animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
        animationControllerHasPendingWork: animationControllerHasPendingWork,
        dropEligibilityBlockers: droppedFrameBlockers(from: decision),
        dropDecision: decision?.action.rawValue ?? "-",
        dropGeneration: renderGeneration.rawValue,
        newestDesiredAtDrop: newestDesiredGeneration.rawValue,
        dropReconciliationMode: reconciliation.mode.rawValue,
        dropReconciliationEffects: reconciliation.effectSummary
      )
    )
  }

  package func formattedWakeCauses(
    _ causes: Set<WakeCause>
  ) -> String {
    let values = causes.map(\.rawValue).sorted()
    return values.isEmpty ? "-" : values.joined(separator: "+")
  }

  package func formattedAnimationRequest(
    _ request: AnimationRequest
  ) -> String {
    switch request {
    case .inherit:
      "inherit"
    case .disabled:
      "disabled"
    case .animate:
      "animate"
    }
  }

  private func zeroArtifactRecord(
    frameNumber: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderGeneration: RenderGeneration,
    runtimeIssues: [RuntimeIssue],
    staleFramePolicy: String,
    tailJobState: String,
    tailCancelReason: String,
    newestDesiredAtTailResult: UInt64,
    animationControllerActiveAnimationCount: Int,
    animationControllerHasPendingWork: Bool,
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>,
    dropDecision: String,
    dropGeneration: UInt64?,
    newestDesiredAtDrop: UInt64?,
    dropReconciliationMode: String,
    dropReconciliationEffects: String
  ) -> FrameDiagnosticRecord {
    FrameDiagnosticRecord(
      frameNumber: frameNumber,
      causeSummary: causeSummary(for: scheduledFrame),
      focusSyncRerenders: 0,
      invalidatedIdentityCount: scheduledFrame.invalidatedIdentities.count,
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
      renderGenerations: .init(render: renderGeneration),
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
      animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: animationControllerHasPendingWork,
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
      runtimeIssues: runtimeIssues,
      staleFramePolicy: staleFramePolicy,
      tailJobState: tailJobState,
      tailCancelReason: tailCancelReason,
      cancelledRenderCount: cancelledRenderCount,
      newestDesiredAtTailStart: renderIntentDiagnostics.desiredGeneration,
      newestDesiredAtTailResult: newestDesiredAtTailResult,
      dropEligibilityBlockers: dropEligibilityBlockers,
      dropDecision: dropDecision,
      dropGeneration: dropGeneration,
      newestDesiredAtDrop: newestDesiredAtDrop,
      dropReconciliationMode: dropReconciliationMode,
      dropReconciliationEffects: dropReconciliationEffects,
      presentationRecoveryAfterDrop: false,
      inputEventsQueuedDuringRenderSuspension:
        renderSuspensionDiagnostics
        .drainInputEventsQueuedDuringSuspension(),
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
      totalFrameDuration: .zero
    )
  }

  private func causeSummary(for scheduledFrame: ScheduledFrame) -> String {
    scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
  }

  private func frameDropEligibilityBlockers(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    focusGraphChanged: Bool,
    focusBindingChanged: Bool,
    focusedValuesChanged: Bool,
    scrollPositionChanged: Bool,
    preferenceObservationChanged: Bool,
    diagnosticsRequireFullRecord: Bool
  ) -> Set<FrameDropEligibility.Blocker> {
    var additionalBlockers = renderer.internalAnimationController.frameDropEligibilityBlockers
    if focusGraphChanged {
      additionalBlockers.insert(.focusGraph)
    }
    if focusBindingChanged {
      additionalBlockers.insert(.focusBindingSync)
    }
    if focusedValuesChanged {
      additionalBlockers.insert(.focusedValueSync)
    }
    if scrollPositionChanged {
      additionalBlockers.insert(.scrollSync)
    }
    if preferenceObservationChanged {
      additionalBlockers.insert(.preferenceObservationDelta)
    }
    if scheduledFrame.animationRequest != .inherit {
      additionalBlockers.insert(.animationTransaction)
    }
    if diagnosticsRequireFullRecord {
      additionalBlockers.insert(.diagnosticsFullRecord)
    }
    return FrameDropEligibility.classify(
      artifacts,
      additionalBlockers: additionalBlockers
    ).blockers
  }

  private func droppedFrameBlockers(
    from decision: CompletedFrameDropDecision?
  ) -> Set<FrameDropEligibility.Blocker> {
    guard let decision else {
      return []
    }
    switch decision.eligibility {
    case .mustCommit(let blockers):
      return blockers
    case .canDropVisualOnly:
      return []
    }
  }
}
