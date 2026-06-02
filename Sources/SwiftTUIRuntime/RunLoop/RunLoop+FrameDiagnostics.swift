import SwiftTUICore

extension RunLoop {
  @MainActor
  func emitCommittedFrameSample(
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
    guard let frameSink else {
      return
    }
    let inputEventsQueuedDuringRenderSuspension =
      renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
    let dropEligibilityBlockers = frameDropEligibilityBlockers(
      artifacts: artifacts,
      scheduledFrame: scheduledFrame,
      focusGraphChanged: focusGraphChanged,
      focusBindingChanged: focusBindingChanged,
      focusedValuesChanged: focusedValuesChanged,
      scrollPositionChanged: scrollPositionChanged,
      preferenceObservationChanged: preferenceObservationChanged
    )

    let sample = CommittedFrameSample(
      frameNumber: renderedFrames,
      scheduledFrame: scheduledFrame,
      diagnostics: artifacts.diagnostics,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
      coalescedWakeCauses: renderIntentDiagnostics.coalescedWakeCauses,
      intentRequestCount: renderIntentDiagnostics.intentRequestCount,
      focusSyncRerenders: focusSyncRerenders,
      animationControllerActiveAnimationCount: renderer
        .internalAnimationController.activeAnimationCount,
      animationControllerHasPendingWork: animationControllerHasPendingWork,
      cancelledRenderCount: cancelledRenderCount,
      inputEventsQueuedDuringRenderSuspension: inputEventsQueuedDuringRenderSuspension,
      dropEligibilityBlockers: dropEligibilityBlockers,
      completedFrameDropDecision: completedFrameDropDecision,
      tailJobState: tailJobState,
      presentationMetrics: presentationMetrics,
      presentationDuration: presentationDuration
    )
    frameSink.record(.committed(sample))
  }

  @MainActor
  func emitElidedFrame(
    renderedFrames: Int,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics
  ) {
    guard let frameSink else {
      return
    }
    let sample = ElidedFrameSample(
      frameNumber: renderedFrames,
      scheduledFrame: scheduledFrame,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
      coalescedWakeCauses: renderIntentDiagnostics.coalescedWakeCauses,
      intentRequestCount: renderIntentDiagnostics.intentRequestCount,
      animationControllerActiveAnimationCount: renderer
        .internalAnimationController.activeAnimationCount,
      animationControllerHasPendingWork: renderer
        .internalAnimationController.lastTickResult.hasPendingWork,
      cancelledRenderCount: cancelledRenderCount,
      timings: renderer.elidedFrameTimings
    )
    frameSink.record(.elided(sample))
  }

  @MainActor
  func emitCancelledFrameTail(
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
    guard let frameSink else {
      return
    }
    let inputEventsQueuedDuringRenderSuspension =
      renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
    let sample = ZeroArtifactFrameSample(
      frameNumber: renderedFrames + 1,
      scheduledFrame: scheduledFrame,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
      coalescedWakeCauses: renderIntentDiagnostics.coalescedWakeCauses,
      intentRequestCount: renderIntentDiagnostics.intentRequestCount,
      renderGeneration: renderGeneration,
      runtimeIssues: runtimeIssues,
      staleFramePolicy: "cancel_pending_before_start",
      tailJobState: tailJobState.rawValue,
      tailCancelReason: tailCancelReason,
      newestDesiredAtTailResult: nextRenderIntentGeneration,
      animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: animationControllerHasPendingWork,
      cancelledRenderCount: cancelledRenderCount,
      inputEventsQueuedDuringRenderSuspension: inputEventsQueuedDuringRenderSuspension,
      dropEligibilityBlockers: [],
      dropDecision: "-",
      dropGeneration: nil,
      newestDesiredAtDrop: nil,
      dropReconciliationMode: "-",
      dropReconciliationEffects: "-"
    )
    frameSink.record(.zeroArtifact(sample))
  }

  @MainActor
  func emitDroppedCompletedFrame(
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
    guard let frameSink else {
      return
    }
    let reconciliation =
      decision?.reconciliation
      ?? .blocked(
        reason: .dropEligibilityBlockers
      )
    let inputEventsQueuedDuringRenderSuspension =
      renderSuspensionDiagnostics.drainInputEventsQueuedDuringSuspension()
    let sample = ZeroArtifactFrameSample(
      frameNumber: renderedFrames + 1,
      scheduledFrame: scheduledFrame,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches,
      coalescedWakeCauses: renderIntentDiagnostics.coalescedWakeCauses,
      intentRequestCount: renderIntentDiagnostics.intentRequestCount,
      renderGeneration: renderGeneration,
      runtimeIssues: runtimeIssues,
      staleFramePolicy: "drop_completed_visual_only",
      tailJobState: FrameTailJobState.droppedCompleted.rawValue,
      tailCancelReason: "-",
      newestDesiredAtTailResult: newestDesiredGeneration.rawValue,
      animationControllerActiveAnimationCount: animationControllerActiveAnimationCount,
      animationControllerHasPendingWork: animationControllerHasPendingWork,
      cancelledRenderCount: cancelledRenderCount,
      inputEventsQueuedDuringRenderSuspension: inputEventsQueuedDuringRenderSuspension,
      dropEligibilityBlockers: droppedFrameBlockers(from: decision),
      dropDecision: decision?.action.rawValue ?? "-",
      dropGeneration: renderGeneration.rawValue,
      newestDesiredAtDrop: newestDesiredGeneration.rawValue,
      dropReconciliationMode: reconciliation.mode.rawValue,
      dropReconciliationEffects: reconciliation.effectSummary
    )
    frameSink.record(.zeroArtifact(sample))
  }
}
