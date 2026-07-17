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
    let outcome = await renderFrameArtifactsForCurrentMode(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      eventPump: eventPump,
      renderIntentDiagnostics: renderIntentDiagnostics,
      renderedFrames: renderedFrames,
      convergence: convergence
    )
    switch outcome {
    case .rendered, .elided:
      // This acquisition COMMITTED — its registration publication just
      // rewrote the live registries — but `applyCommittedFrame`'s
      // retained-store absorb may never run for it: an elided commit
      // produces no frame artifacts at all, and a focus-sync convergence
      // re-render commits its pass, folds the unapplied commit plan into
      // the lifecycle carry-forward, and loops. A later pass's scoped
      // publication can then remove a registration NO store ever
      // witnessed — the owner's record was legitimately reset by a
      // re-evaluation that did not re-trigger — and the carried-forward
      // committed callback skips at dispatch (gallery fuzzer find,
      // 2026-07-17 §5 residual: sheet `onChange` under focus-sync
      // convergence). Absorb every committed publication here, at the
      // seam where the commit is known, so deferred plans always find
      // their closures in the retained store.
      lifecycleCoordinator.absorbPublishedRegistrations(
        localLifecycleRegistry.snapshot()
      )
    case .skipped:
      // Cancelled-before-start / dropped-completed: nothing committed, the
      // live registries are unchanged — nothing new to absorb.
      break
    }
    return outcome
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
      switch renderer.renderEliding(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal(),
        elisionCauses: scheduledFrame.causes,
        elisionHasExplicitAnimationTransactions: scheduledFrame
          .hasExplicitAnimationTransactions
      ) {
      case .rendered(let renderedArtifacts):
        return .rendered(renderedArtifacts, .completed, nil)
      case .elided:
        return .elided
      }
    }
    if eventPump == nil {
      switch await renderer.renderAsyncEliding(
        viewBuilder(
          (
            state: currentState,
            focusedIdentity: focusTracker.currentFocusIdentity
          )),
        context: resolveContext(for: scheduledFrame),
        proposal: proposal(),
        elisionCauses: scheduledFrame.causes,
        elisionHasExplicitAnimationTransactions: scheduledFrame
          .hasExplicitAnimationTransactions
      ) {
      case .rendered(let renderedArtifacts):
        return .rendered(renderedArtifacts, .completed, nil)
      case .elided:
        return .elided
      }
    }

    let renderOutcome: CancellableRenderOutcome
    switch await acquireCancellableFrameArtifacts(
      scheduledFrame: scheduledFrame,
      currentState: currentState,
      renderIntentDiagnostics: renderIntentDiagnostics
    ) {
    case .rendered(let outcome):
      renderOutcome = outcome
    case .elided:
      // The elided commit published state — progress happened.
      consecutivePreStartCancelCount = 0
      return .elided
    }
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
  ) async -> CancellableRenderExecutionResult {
    await renderer.renderAsyncCancellableEliding(
      viewBuilder(
        (
          state: currentState,
          focusedIdentity: focusTracker.currentFocusIdentity
        )),
      context: resolveContext(for: scheduledFrame),
      proposal: proposal(),
      elisionCauses: scheduledFrame.causes,
      elisionHasExplicitAnimationTransactions: scheduledFrame
        .hasExplicitAnimationTransactions,
      newestDesiredGeneration: {
        RenderGeneration(
          self.scheduler.hasPendingFrame(at: .now())
            ? self.nextRenderIntentGeneration
            : renderIntentDiagnostics.desiredGeneration
        )
      },
      completedFramePolicy: (renderMode == .asyncNoCancel || renderMode == .asyncNoDrop)
        ? .orderedCommitOnly : nil,
      completedFrameAdditionalBlockers: { artifacts in
        self.completedFrameAdditionalDropBlockers(
          artifacts: artifacts,
          scheduledFrame: scheduledFrame
        )
      },
      redundantHandlerInstallationsAreVisualOnly: { artifacts in
        self.completedFrameHasStableInteractionRouting(artifacts: artifacts)
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
    // Forward-progress bound for the pre-start cancel path (the tab-leave
    // livelock, report 2026-07-05-001): a prepared frame whose commit would
    // stop an invalidation source — a tab leave carrying the leaving tab's
    // `taskCancel` — is superseded by that source on every cycle, so after
    // `maxConsecutivePreStartCancels` consecutive newer-intent cancels the
    // queued tail must run. The completed-frame policy still decides
    // commit-vs-drop for it, so input coalescing degrades gracefully: a
    // forced tail that is genuinely visual-only and superseded is dropped,
    // itself bounded by `progress_starvation`.
    guard consecutivePreStartCancelCount < Self.maxConsecutivePreStartCancels else {
      // Trace-visible, like the completed-frame policy's progress_starvation:
      // the queued tail this decision protects will run uncancellable. The
      // event has no frame number of its own — it precedes the acquisition
      // it protects.
      progressProbe?.record(
        .preStartCancelBoundHeld,
        frameNumber: 0
      )
      return false
    }
    return scheduler.hasPendingFrame(at: .now())
  }

  private func awaitQueuedTailCancellationSignalForMode() async {
    guard renderMode != .asyncNoCancel else {
      return
    }
    // At the forward-progress bound the queued tail is not cancellable, so
    // there is no signal to wait for (see `shouldCancelQueuedTailForMode`).
    guard consecutivePreStartCancelCount < Self.maxConsecutivePreStartCancels else {
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
