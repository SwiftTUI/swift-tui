import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
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

}
