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

    diagnosticsLogger.log(
      committedFrameDiagnosticRecord(
        artifacts: artifacts,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        focusSyncRerenders: focusSyncRerenders,
        focusGraphChanged: focusGraphChanged,
        focusBindingChanged: focusBindingChanged,
        focusedValuesChanged: focusedValuesChanged,
        scrollPositionChanged: scrollPositionChanged,
        preferenceObservationChanged: preferenceObservationChanged,
        tailJobState: tailJobState,
        completedFrameDropDecision: completedFrameDropDecision,
        animationControllerHasPendingWork: animationControllerHasPendingWork,
        presentationMetrics: presentationMetrics,
        presentationDuration: presentationDuration,
        renderedFrames: renderedFrames
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
}
