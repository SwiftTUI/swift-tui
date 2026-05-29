import SwiftTUICore

/// A single diagnostic record capturing one rendered frame's performance data.
public struct FrameDiagnosticRecord: Sendable {
  public var frameNumber: Int
  public var causeSummary: String
  public var focusSyncRerenders: Int
  public var invalidatedIdentityCount: Int
  public var resolvedNodeCount: Int
  public var resolvedNodesComputed: Int
  public var resolvedNodesReused: Int
  public var measuredNodeCount: Int
  public var measuredNodesComputed: Int
  public var measuredNodesReused: Int
  public var placedNodeCount: Int
  public var drawNodeCount: Int
  public var interactionRegionCount: Int
  public var focusRegionCount: Int
  public var phaseTimings: FramePhaseTimings?
  public var renderGenerations: FrameRenderGenerations
  public var desiredGeneration: UInt64
  public var coalescedEventBatches: Int
  public var coalescedWakeCauses: String
  /// Total `request*` calls the scheduler coalesced into this frame.
  /// `> 1` indicates cancellation pressure for Stage 3D rollout.
  public var coalescedIntentRequests: Int
  public var scheduledAnimationRequest: String
  public var scheduledAnimationBatchID: UInt64?
  public var animationControllerActiveAnimationCount: Int
  public var animationControllerHasPendingWork: Bool
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: String?
  public var layoutDependentRealizations: Int
  public var layoutDependentRealizationCacheHits: Int
  public var layoutDependentMainActorFallbacks: Int
  public var geometryAnchorResolutionMissCount: Int
  public var firstGeometryAnchorResolutionMissIdentity: String?
  public var geometryMissingNamedCoordinateSpaceCount: Int
  public var firstGeometryMissingNamedCoordinateSpaceName: String?
  public var geometryDuplicateNamedCoordinateSpaceCount: Int
  public var firstGeometryDuplicateNamedCoordinateSpaceName: String?
  public var runtimePointerHandlerCount: Int
  public var runtimePointerHoverHandlerCount: Int
  public var runtimeGestureRecognizerCount: Int
  public var runtimeGestureStateBindingCount: Int
  public var runtimeIssues: [RuntimeIssue]
  public var staleFramePolicy: String
  public var tailJobState: String
  public var tailCancelReason: String
  public var cancelledRenderCount: Int
  public var newestDesiredAtTailStart: UInt64?
  public var newestDesiredAtTailResult: UInt64?
  public var dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
  public var dropDecision: String
  public var dropGeneration: UInt64?
  public var newestDesiredAtDrop: UInt64?
  public var dropReconciliationMode: String
  public var dropReconciliationEffects: String
  public var presentationRecoveryAfterDrop: Bool
  public var inputEventsQueuedDuringRenderSuspension: Int
  public var presentationStrategy: String
  public var presentationBytesWritten: Int
  public var presentationLinesTouched: Int
  public var presentationCellsChanged: Int
  public var presentationDuration: Duration
  public var damageRowCount: Int?
  public var damageRangeAwareRowCount: Int?
  public var damageTextSpanCount: Int?
  public var damageTextCellCount: Int?
  public var damageGraphicsInvalidationCount: Int?
  public var damageRequiresFullTextRepaint: Bool
  public var damageRequiresFullGraphicsReplay: Bool
  public var presentationUsedSynchronizedOutput: Bool
  public var presentationGraphicsReplayScope: String
  public var presentationGraphicsAttachmentsReplayed: Int
  public var presentationEditOperationLowering: String
  public var presentationEditOperationCount: Int
  public var measurementCacheHitRate: Double?
  public var totalFrameDuration: Duration
  /// Whether this frame was elided (skipped) because all drawn identities
  /// were off-screen. Defaults to `false`; set to `true` by the run loop
  /// when off-screen frame elision fires (wired in a later task).
  public var elided: Bool
}

extension FrameDiagnosticRecord {
  package init(
    frameNumber: Int,
    causeSummary: String,
    renderGenerations: FrameRenderGenerations = .init(),
    desiredGeneration: UInt64 = 0,
    presentationStrategy: String = "-",
    presentationDuration: Duration = .zero,
    totalFrameDuration: Duration = .zero
  ) {
    self.frameNumber = frameNumber
    self.causeSummary = causeSummary
    focusSyncRerenders = 0
    invalidatedIdentityCount = 0
    resolvedNodeCount = 0
    resolvedNodesComputed = 0
    resolvedNodesReused = 0
    measuredNodeCount = 0
    measuredNodesComputed = 0
    measuredNodesReused = 0
    placedNodeCount = 0
    drawNodeCount = 0
    interactionRegionCount = 0
    focusRegionCount = 0
    phaseTimings = nil
    self.renderGenerations = renderGenerations
    self.desiredGeneration = desiredGeneration
    coalescedEventBatches = 0
    coalescedWakeCauses = "-"
    coalescedIntentRequests = 0
    scheduledAnimationRequest = "-"
    scheduledAnimationBatchID = nil
    animationControllerActiveAnimationCount = 0
    animationControllerHasPendingWork = false
    workerTimings = nil
    mainActorTimings = nil
    customLayoutFallbackCount = 0
    firstCustomLayoutFallbackIdentity = nil
    layoutDependentRealizations = 0
    layoutDependentRealizationCacheHits = 0
    layoutDependentMainActorFallbacks = 0
    geometryAnchorResolutionMissCount = 0
    firstGeometryAnchorResolutionMissIdentity = nil
    geometryMissingNamedCoordinateSpaceCount = 0
    firstGeometryMissingNamedCoordinateSpaceName = nil
    geometryDuplicateNamedCoordinateSpaceCount = 0
    firstGeometryDuplicateNamedCoordinateSpaceName = nil
    runtimePointerHandlerCount = 0
    runtimePointerHoverHandlerCount = 0
    runtimeGestureRecognizerCount = 0
    runtimeGestureStateBindingCount = 0
    runtimeIssues = []
    staleFramePolicy = "-"
    tailJobState = "-"
    tailCancelReason = "-"
    cancelledRenderCount = 0
    newestDesiredAtTailStart = nil
    newestDesiredAtTailResult = nil
    dropEligibilityBlockers = []
    dropDecision = "-"
    dropGeneration = nil
    newestDesiredAtDrop = nil
    dropReconciliationMode = "-"
    dropReconciliationEffects = "-"
    presentationRecoveryAfterDrop = false
    inputEventsQueuedDuringRenderSuspension = 0
    self.presentationStrategy = presentationStrategy
    presentationBytesWritten = 0
    presentationLinesTouched = 0
    presentationCellsChanged = 0
    self.presentationDuration = presentationDuration
    damageRowCount = nil
    damageRangeAwareRowCount = nil
    damageTextSpanCount = nil
    damageTextCellCount = nil
    damageGraphicsInvalidationCount = nil
    damageRequiresFullTextRepaint = false
    damageRequiresFullGraphicsReplay = false
    presentationUsedSynchronizedOutput = false
    presentationGraphicsReplayScope = "-"
    presentationGraphicsAttachmentsReplayed = 0
    presentationEditOperationLowering = "-"
    presentationEditOperationCount = 0
    measurementCacheHitRate = nil
    self.totalFrameDuration = totalFrameDuration
    elided = false
  }
}
