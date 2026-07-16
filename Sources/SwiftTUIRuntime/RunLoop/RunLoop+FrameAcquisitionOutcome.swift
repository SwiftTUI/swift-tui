import SwiftTUICore

extension RunLoop {
  /// Outcome of the async artifact-acquisition strategy for one focus-sync
  /// iteration. Models the strategy boundary from ADR-0021: `.rendered`
  /// carries a frame plus its tail state; `.skipped` reports that the tail
  /// job was cancelled-before-start or dropped-completed and the enclosing
  /// frame must be abandoned without invoking the shared per-frame body;
  /// `.elided` reports that the off-screen elision gate fired — the reduced
  /// commit already ran (firing completions and publishing animation state),
  /// so the frame must reschedule the next deadline and emit its diagnostic
  /// without running the tail or presenting.
  enum FrameAcquisitionOutcome {
    case rendered(FrameArtifacts, FrameTailJobState, CompletedFrameDropDecision?)
    case skipped
    case elided
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
      // Only newer-intent cancels count toward the forward-progress bound: a
      // stale-baseline skip means a sibling frame committed (progress
      // happened), so it resets the run instead.
      if renderOutcome.tailCancelReason == "newer_render_intent" {
        consecutivePreStartCancelCount += 1
      } else {
        consecutivePreStartCancelCount = 0
      }
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      cancelledRenderCount += 1
      replayCancelledFrameIntent(scheduledFrame)
      emitCancelledFrameTail(
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
      // The tail ran to completion — the pre-start cancel run is broken.
      // Drop starvation is separately bounded by `progress_starvation`.
      consecutivePreStartCancelCount = 0
      reportRuntimeIssues(renderOutcome.runtimeIssues)
      appendLifecycleCarryForward(
        convergence.lifecycleCarryForward,
        into: &deferredLifecycleCarryForward
      )
      emitDroppedCompletedFrame(
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
      // No reset here: a COMPLETED convergence pass can still belong to a
      // frame that a later pass abandons, and resetting per pass lets an
      // input frame's multi-pass convergence stretch the pre-start cancel
      // run past the bound. The reset for genuinely applied frames lives in
      // `applyAcquiredFrame`.
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
    if scheduledFrame.hasExplicitAnimationTransactions {
      blockers.insert(.animationTransaction)
    }
    if artifacts.semanticSnapshot.focusRegions != latestSemanticSnapshot.focusRegions {
      blockers.insert(.focusGraph)
    }
    if artifacts.semanticSnapshot.scrollRoutes != latestSemanticSnapshot.scrollRoutes
      || artifacts.semanticSnapshot.scrollTargets != latestSemanticSnapshot.scrollTargets
      || artifacts.semanticSnapshot.selectionRoutes != latestSemanticSnapshot.selectionRoutes
    {
      blockers.insert(.scrollSync)
    }
    return blockers
  }

  func completedFrameHasStableInteractionRouting(
    artifacts: FrameArtifacts
  ) -> Bool {
    let snapshot = artifacts.semanticSnapshot
    return snapshot.interactionRegions == latestSemanticSnapshot.interactionRegions
      && snapshot.focusRegions == latestSemanticSnapshot.focusRegions
      && snapshot.navigationRoutes == latestSemanticSnapshot.navigationRoutes
      && snapshot.scrollRoutes == latestSemanticSnapshot.scrollRoutes
      && snapshot.scrollTargets == latestSemanticSnapshot.scrollTargets
      && snapshot.selectionRoutes == latestSemanticSnapshot.selectionRoutes
      && snapshot.namedCoordinateSpaces == latestSemanticSnapshot.namedCoordinateSpaces
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
