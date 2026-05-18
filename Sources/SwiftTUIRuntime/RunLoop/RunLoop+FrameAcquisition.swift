import SwiftTUICore
import SwiftTUIViews

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

  /// Strategy-specific artifact acquisition for the async driver. Renders
  /// one tree according to `renderMode`: a synchronous render for `.sync`,
  /// `renderAsync` when no event pump is attached, otherwise the cancellable
  /// frame-tail renderer. Cancelled-before-start and dropped-completed tail
  /// outcomes are reported, logged, have their accumulated focus-sync
  /// lifecycle carry-forward folded back into `deferredLifecycleCarryForward`,
  /// and are surfaced as `.skipped` here so the shared focus-sync loop and
  /// per-frame body never see them.
  ///
  /// `renderedFrames` is passed by value: cancelled/dropped tails never
  /// increment the committed frame count — only `applyAcquiredFrame` does,
  /// after acquisition succeeds — but the current count is still needed so
  /// the cancelled/dropped diagnostic records carry the correct frame number.
  func acquireFrameArtifactsAsync(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    eventPump: EventPump?,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) async -> FrameAcquisitionOutcome {
    await renderFrameArtifactsForCurrentMode(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      eventPump: eventPump,
      renderIntentDiagnostics: renderIntentDiagnostics,
      renderedFrames: renderedFrames,
      convergence: convergence
    )
  }

  private func renderFrameArtifactsForCurrentMode(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    eventPump: EventPump?,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    renderedFrames: Int,
    convergence: FocusSyncConvergenceState
  ) async -> FrameAcquisitionOutcome {
    if renderMode == .sync {
      let renderedArtifacts = renderer.render(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal()
      )
      return .rendered(renderedArtifacts, .completed, nil)
    }
    if eventPump == nil {
      let renderedArtifacts = await renderer.renderAsync(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal()
      )
      return .rendered(renderedArtifacts, .completed, nil)
    }

    let renderOutcome = await acquireCancellableFrameArtifacts(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      renderIntentDiagnostics: renderIntentDiagnostics
    )
    if let skippedFrame = recordSkippedCancellableFrame(
      renderOutcome,
      scheduledFrame: scheduledFrame,
      renderIntentDiagnostics: renderIntentDiagnostics,
      renderedFrames: renderedFrames,
      convergence: convergence
    ) {
      return skippedFrame
    }
    guard let outcomeArtifacts = renderOutcome.artifacts else {
      preconditionFailure("Completed render outcome did not include frame artifacts.")
    }
    return .rendered(
      outcomeArtifacts,
      renderOutcome.tailJobState,
      renderOutcome.completedFrameDropDecision
    )
  }

  private func acquireCancellableFrameArtifacts(
    scheduledFrame: ScheduledFrame,
    currentState: State,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics
  ) async -> CancellableRenderOutcome {
    await renderer.renderAsyncCancellable(
      viewBuilder(
        (
          state: currentState,
          focusedIdentity: focusTracker.currentFocusIdentity
        )),
      context: resolveContext(for: scheduledFrame),
      proposal: proposal(),
      newestDesiredGeneration: {
        RenderGeneration(
          self.scheduler.hasPendingFrame(at: .now())
            ? self.nextRenderIntentGeneration
            : renderIntentDiagnostics.desiredGeneration
        )
      },
      completedFramePolicy: renderMode == .asyncNoDrop ? .orderedCommitOnly : nil,
      completedFrameAdditionalBlockers: { artifacts in
        self.completedFrameAdditionalDropBlockers(
          artifacts: artifacts,
          scheduledFrame: scheduledFrame
        )
      },
      awaitQueuedCancellationSignal: awaitQueuedTailCancellationSignalForMode,
      shouldCancelQueued: shouldCancelQueuedTailForMode
    )
  }

  @MainActor
  private func shouldCancelQueuedTailForMode() async -> Bool {
    guard renderMode != .asyncNoCancel else {
      return false
    }
    return scheduler.hasPendingFrame(at: .now())
  }

  private func awaitQueuedTailCancellationSignalForMode() async {
    guard renderMode != .asyncNoCancel else {
      return
    }
    guard !scheduler.hasPendingFrame(at: .now()) else {
      return
    }
    guard let pendingFrameAwaiter = scheduler as? any PendingFrameAwaiting else {
      return
    }
    await pendingFrameAwaiter.waitForPendingFrame(at: .now())
  }

  private func recordSkippedCancellableFrame(
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
      progressProbe?.record(
        .frameSkipped,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        renderGeneration: renderOutcome.renderGeneration.rawValue,
        tailJobState: renderOutcome.tailJobState
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
      progressProbe?.record(
        .frameSkipped,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        renderGeneration: renderOutcome.renderGeneration.rawValue,
        tailJobState: renderOutcome.tailJobState
      )
      return .skipped
    case .queued, .started, .completed:
      return nil
    }
  }

  @MainActor
  private func replayCancelledFrameIntent(_ frame: ScheduledFrame) {
    guard let scheduler = scheduler as? any CancelledFrameIntentReplaying else {
      return
    }
    scheduler.replayCancelledFrameIntent(frame)
  }

  private func completedFrameAdditionalDropBlockers(
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
}
