import SwiftTUICore

extension RunLoop {
  /// Outcome of the async artifact-acquisition strategy for one focus-sync
  /// iteration. Models the strategy boundary from ADR-0021: `.rendered`
  /// carries a frame plus its tail state; `.skipped` reports that the tail
  /// job was cancelled-before-start or dropped-completed and the enclosing
  /// frame must be abandoned without invoking the shared per-frame body.
  enum FrameAcquisitionOutcome {
    case rendered(FrameArtifacts, FrameTailJobState, CompletedFrameDropDecision?)
    case skipped
  }

  func recordSkippedCancellableFrame(
    _ renderOutcome: CancellableRenderOutcome,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) -> FrameAcquisitionOutcome? {
    switch renderOutcome.tailJobState {
    case .cancelledBeforeStart:
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      cancelledRenderCount += 1
      replayCancelledFrameIntent(scheduledFrame)
      logCancelledFrameTail(
        diagnosticsLogger: diagnosticsLogger,
        renderedFrames: renderedFrames,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderOutcome.renderGeneration,
        runtimeIssues: renderOutcome.runtimeIssues,
        tailJobState: renderOutcome.tailJobState,
        tailCancelReason: renderOutcome.tailCancelReason ?? "-",
        animationControllerActiveAnimationCount: renderer
          .internalAnimationController.activeAnimationCount,
        animationControllerHasPendingWork: renderer
          .internalAnimationController.lastTickResult.hasPendingWork
      )
      recordSkippedFrameProgress(
        renderedFrames: renderedFrames,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderOutcome: renderOutcome
      )
      return .skipped
    case .droppedCompleted:
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      logDroppedCompletedFrame(
        diagnosticsLogger: diagnosticsLogger,
        renderedFrames: renderedFrames,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderGeneration: renderOutcome.renderGeneration,
        newestDesiredGeneration: renderOutcome.newestDesiredGeneration
          ?? RenderGeneration(nextRenderIntentGeneration),
        decision: renderOutcome.completedFrameDropDecision,
        runtimeIssues: renderOutcome.runtimeIssues,
        animationControllerActiveAnimationCount: renderer
          .internalAnimationController.activeAnimationCount,
        animationControllerHasPendingWork: renderer
          .internalAnimationController.lastTickResult.hasPendingWork
      )
      recordSkippedFrameProgress(
        renderedFrames: renderedFrames,
        renderIntentDiagnostics: renderIntentDiagnostics,
        renderOutcome: renderOutcome
      )
      return .skipped
    case .queued, .started, .completed:
      return nil
    }
  }

  @MainActor
  func replayCancelledFrameIntent(_ frame: ScheduledFrame) {
    guard let scheduler = scheduler as? any CancelledFrameIntentReplaying else {
      return
    }
    scheduler.replayCancelledFrameIntent(frame)
  }

  func completedFrameAdditionalDropBlockers(
    artifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame
  ) -> Set<FrameDropEligibility.Blocker> {
    var blockers = renderer.internalAnimationController.frameDropEligibilityBlockers
    if scheduledFrame.animationRequest != .inherit {
      blockers.insert(.animationTransaction)
    }
    if !artifacts.semanticSnapshot.focusRegions.isEmpty {
      blockers.insert(.focusGraph)
    }
    if !artifacts.semanticSnapshot.scrollRoutes.isEmpty {
      blockers.insert(.scrollSync)
    }
    return blockers
  }

  private func recordSkippedFrameProgress(
    renderedFrames: Int,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderOutcome: CancellableRenderOutcome
  ) {
    progressProbe?.record(
      .frameSkipped,
      frameNumber: renderedFrames + 1,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      renderGeneration: renderOutcome.renderGeneration.rawValue,
      tailJobState: renderOutcome.tailJobState
    )
  }
}
