import SwiftTUICore

// Diagnostic record assembly for frames that produce no artifacts.
//
// `RunLoop+FrameDiagnosticRecordAssembly.swift` assembles the record for a
// normally rendered frame. This file owns the zero-artifact variant — used
// when a frame is dropped or otherwise produces no pipeline products — plus
// the small value formatters both paths share.
extension RunLoop {
  func formattedWakeCauses(
    _ causes: Set<WakeCause>
  ) -> String {
    let values = causes.map(\.rawValue).sorted()
    return values.isEmpty ? "-" : values.joined(separator: "+")
  }

  func formattedAnimationRequest(
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

  func zeroArtifactRecord(
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
}
