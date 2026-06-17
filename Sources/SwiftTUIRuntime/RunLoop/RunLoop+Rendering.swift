import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  // MARK: - Frame driver (F2: unified sync/async per-frame body, ADR-0021)

  /// Synchronous frame driver, retained as a test entry point.
  ///
  /// This driver predates off-screen frame elision and intentionally does not
  /// include an `.elided` arm. Production drives the run loop exclusively
  /// through ``renderPendingFramesAsync(renderedFrames:eventPump:)``, which is
  /// fully wired to the elision gate via `acquireFrameArtifactsAsync`. This
  /// function is only invoked from synchronous test helpers; adding elision
  /// complexity here would serve no production path.
  package func renderPendingFrames(renderedFrames: inout Int) throws {
    observationBridge.attachInvalidator(scheduler)

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    while var scheduledFrame = scheduler.consumeReadyFrame(at: frameReadinessClock()) {
      let currentState = stateContainer.state
      scheduledFrame = scheduledFrameByReconcilingExternalState(
        scheduledFrame,
        currentState: currentState
      )
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      progressProbe?.record(
        .frameIntent,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches
      )
      drainGestureDeadlinesIfNeeded(for: scheduledFrame)
      var convergence = FocusSyncConvergenceState()
      convergence.lifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)

      let retainedReuseSuppressionScope = retainedReuseSuppressionScopeForFrameSafety()
      var artifacts: FrameArtifacts?
      while true {
        if convergence.rerenderedForFocusSync || !retainedReuseSuppressionScope.isEmpty {
          renderer.forceRootEvaluation()
        }
        if !retainedReuseSuppressionScope.isEmpty {
          // Reuse-unsafe identities: forcing root evaluation only makes the
          // walk *reach* every node — each reached node still independently
          // chooses reuse — so suppress the fast path for the affected scope.
          // Focus-sync rerenders still keep reuse to carry first-pass
          // measurement/scroll state across the convergence loop.
          renderer.suppressRetainedReuseForNextFrame(retainedReuseSuppressionScope)
        }
        let renderedArtifacts = renderer.render(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal()
        )
        artifacts = renderedArtifacts
        let outcome = try processFocusSyncIteration(
          renderedArtifacts,
          convergence: &convergence
        )
        switch outcome {
        case .rerender:
          if convergence.budgetExceeded {
            break
          }
          continue
        case .converged:
          break
        }
        break
      }

      guard let artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      try applyAcquiredFrame(
        artifacts,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: FrameAcquisitionState(),
        hasFrameSink: hasFrameSink,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState
    }
    progressProbe?.record(.schedulerIdle, frameNumber: renderedFrames)
  }

  /// Shared post-acquisition per-frame body. Both `renderPendingFrames` and
  /// `renderPendingFramesAsync` delegate to this once their (differing)
  /// artifact-acquisition strategy has produced a converged frame. Every
  /// line here is classified `structural` in ADR-0021: lifecycle
  /// carry-forward merge, accessibility announcements, focus presentation,
  /// frame presentation, preference-observation reconciliation,
  /// animation-deadline rescheduling, observation pruning, and the full
  /// `FrameDiagnosticRecord` construction.
  private func applyAcquiredFrame(
    _ acquiredArtifacts: FrameArtifacts,
    scheduledFrame: ScheduledFrame,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    convergence: FocusSyncConvergenceState,
    acquisition: FrameAcquisitionState,
    hasFrameSink: Bool,
    renderedFrames: inout Int
  ) throws {
    var artifacts = acquiredArtifacts
    reportRuntimeIssues(artifacts.diagnostics.runtime.issues)
    mergeLifecycleCarryForward(
      convergence.lifecycleCarryForward,
      into: &artifacts.commitPlan.lifecycle
    )
    appendPendingAccessibilityAnnouncements(to: &artifacts)
    latestSemanticSnapshot = artifacts.semanticSnapshot
    if convergence.budgetExceeded {
      let causes = scheduledFrame.causes.map(\.rawValue).sorted().joined(separator: "+")
      assertionFailure(
        "Focus synchronization did not converge after \(convergence.rerenderCount) rerenders for frame causes \(causes). The rerender budget was derived from the frame semantic graph."
      )
    }

    let focusPresentation = artifacts.semanticSnapshot.focusPresentation(
      for: focusTracker.currentFocusIdentity
    )
    let presentationResult = try presentCommittedFrameWithDiagnosticsTiming(
      artifacts,
      damage: presentationDamage(for: artifacts, convergence: convergence),
      hasFrameSink: hasFrameSink
    )
    recordPresentedRasterSurface(artifacts.rasterSurface)
    lifecycleCoordinator.applyCommittedFrame(
      plan: artifacts.commitPlan,
      currentLifecycleRegistry: localLifecycleRegistry,
      currentTaskRegistry: localTaskRegistry
    )
    updateFocusPresentation(focusPresentation)
    // Record the committed focus so the next frame's reuse-safety gate can
    // detect a focus move (see ``retainedReuseSuppressionScopeForFrameSafety()``).
    previousFrameFocusIdentity = focusTracker.currentFocusIdentity
    previousFramePressedIdentity = pressedIdentity
    let preferenceObservationChanged = localPreferenceObservationRegistry.applyChanges(
      since: previousPreferenceObservations
    )
    previousPreferenceObservations = localPreferenceObservationRegistry.snapshot()
    flushPostActionInvalidations()
    // After rendering, request the next animation frame deadline
    // whenever the tick reported pending work.  Phase 4 split the
    // tick result so ``hasPendingWork`` is the unambiguous "schedule
    // another frame" signal — including for stranded-batch drains
    // that aren't tied to any visible identity.
    //
    // The viewport gate that used to guard this path
    // (``redrawIdentities.isDisjoint(with: drawnIdentities)``) is
    // gone: its purpose was to quiesce ticks driving animations into
    // clipped subtrees, but the gate had a one-way trap — once a
    // tick produced an empty redraw set the only thing that could
    // restart the loop was another tick.  ``redrawIdentities`` is
    // still consulted by the incremental presentation diff for
    // dirty-region calculation; only the wake-up decision is
    // unconditional now.
    let animationTick = renderer.internalAnimationController.lastTickResult
    requestNextAnimationFrameIfNeeded(animationTick)
    observationBridge.prune(
      keeping: renderer.liveNodeIDSnapshot()
    )
    renderedFrames += 1
    progressProbe?.record(
      .frameCommitted,
      frameNumber: renderedFrames,
      desiredGeneration: renderIntentDiagnostics.desiredGeneration,
      renderGeneration: artifacts.diagnostics.timing.renderGenerations.render.rawValue,
      tailJobState: acquisition.tailJobState
    )

    emitCommittedFrameSample(
      artifacts: artifacts,
      scheduledFrame: scheduledFrame,
      renderIntentDiagnostics: renderIntentDiagnostics,
      focusSyncRerenders: convergence.rerenderCount,
      focusGraphChanged: convergence.focusGraphChanged,
      focusBindingChanged: convergence.focusBindingChanged,
      focusedValuesChanged: convergence.focusedValuesChanged,
      scrollPositionChanged: convergence.scrollPositionChanged,
      preferenceObservationChanged: preferenceObservationChanged,
      tailJobState: acquisition.tailJobState,
      completedFrameDropDecision: acquisition.completedFrameDropDecision,
      animationControllerHasPendingWork: animationTick.hasPendingWork,
      presentationMetrics: presentationResult.metrics,
      presentationDuration: presentationResult.duration,
      renderedFrames: renderedFrames
    )

    if let transientPressedIdentity,
      transientPressedIdentity == pressedIdentity
    {
      self.transientPressedIdentity = nil
      setPressedIdentity(nil, transient: false)
    }
  }

  package func updateTerminalPointerHoverModeIfNeeded() throws {
    let shouldEnable = localPointerHandlerRegistry.hasHoverSubscribers
    guard shouldEnable != terminalPointerHoverEnabled else {
      return
    }
    if let terminalCommandSurface =
      presentationSurface as? any TerminalCommandPresentationSurface
    {
      try terminalCommandSurface.setPointerHoverEnabled(shouldEnable)
    }
    terminalPointerHoverEnabled = shouldEnable
  }

  package func renderPendingFramesAsync(renderedFrames: inout Int) async throws {
    _ = try await renderPendingFramesAsync(
      renderedFrames: &renderedFrames,
      eventPump: nil
    )
  }

  package func renderPendingFramesAsync(
    renderedFrames: inout Int,
    eventPump: EventPump?
  ) async throws -> RunLoopExitReason? {
    observationBridge.attachInvalidator(scheduler)

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    frameLoop: while var scheduledFrame = scheduler.consumeReadyFrame(at: frameReadinessClock()) {
      let currentState = stateContainer.state
      scheduledFrame = scheduledFrameByReconcilingExternalState(
        scheduledFrame,
        currentState: currentState
      )
      let renderIntentDiagnostics = nextRenderIntentDiagnostics(for: scheduledFrame)
      progressProbe?.record(
        .frameIntent,
        frameNumber: renderedFrames + 1,
        desiredGeneration: renderIntentDiagnostics.desiredGeneration,
        coalescedEventBatches: renderIntentDiagnostics.coalescedEventBatches
      )
      drainGestureDeadlinesIfNeeded(for: scheduledFrame)
      var convergence = FocusSyncConvergenceState()
      convergence.lifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)

      var acquisition = FrameAcquisitionState()
      var artifacts: FrameArtifacts?
      // The focus-sync convergence loop is the one place the runtime must
      // suspend (the async render). Acquisition is the only strategy
      // difference (ADR-0021); the per-iteration side effects
      // (`processFocusSyncIteration`) and post-acquisition body
      // (`applyAcquiredFrame`) are shared with the synchronous driver.
      let retainedReuseSuppressionScope = retainedReuseSuppressionScopeForFrameSafety()
      convergenceLoop: while true {
        if convergence.rerenderedForFocusSync || !retainedReuseSuppressionScope.isEmpty {
          renderer.forceRootEvaluation()
        }
        if !retainedReuseSuppressionScope.isEmpty {
          // Reuse-unsafe identities: forcing root evaluation only makes the
          // walk *reach* every node — each reached node still independently
          // chooses reuse — so suppress the fast path for the affected scope.
          // Focus-sync rerenders still keep reuse to carry first-pass
          // measurement/scroll state across the convergence loop.
          renderer.suppressRetainedReuseForNextFrame(retainedReuseSuppressionScope)
        }
        let acquired = await acquireFrameArtifactsAsync(
          scheduledFrame: scheduledFrame,
          currentState: currentState,
          eventPump: eventPump,
          renderIntentDiagnostics: renderIntentDiagnostics,
          renderedFrames: renderedFrames,
          convergence: convergence
        )
        switch acquired {
        case .skipped:
          // Tail job was cancelled-before-start or dropped-completed; the
          // acquisition step already reported issues, carried lifecycle
          // forward, and logged the tail. Abandon this frame.
          continue frameLoop
        case .elided:
          // Off-screen elision fired: `commitElidedFrame` (inside the gate
          // closure) already fired deferred completions and published the
          // advanced animation state to live, but no tail ran and nothing
          // was presented. Keep the animation loop alive by rescheduling the
          // next deadline from the now-live tick result, carry lifecycle
          // forward (no tail consumed it), record the diagnostic, advance the
          // frame counter, and abandon the rest of this frame.
          appendLifecycleCarryForward(
            convergence.lifecycleCarryForward,
            into: &deferredLifecycleCarryForward
          )
          requestNextAnimationFrameIfNeeded(
            renderer.internalAnimationController.lastTickResult
          )
          renderedFrames += 1
          emitElidedFrame(
            renderedFrames: renderedFrames,
            scheduledFrame: scheduledFrame,
            renderIntentDiagnostics: renderIntentDiagnostics
          )
          progressProbe?.record(
            .frameCommitted,
            frameNumber: renderedFrames,
            desiredGeneration: renderIntentDiagnostics.desiredGeneration
          )
          previousRenderedState = currentState
          continue frameLoop
        case .rendered(let renderedArtifacts, let tailJobState, let dropDecision):
          acquisition.tailJobState = tailJobState
          acquisition.completedFrameDropDecision = dropDecision
          progressProbe?.record(
            .frameAcquired,
            frameNumber: renderedFrames + 1,
            desiredGeneration: renderIntentDiagnostics.desiredGeneration,
            renderGeneration: renderedArtifacts.diagnostics.timing.renderGenerations.render
              .rawValue,
            tailJobState: tailJobState
          )
          artifacts = renderedArtifacts
          let outcome = try processFocusSyncIteration(
            renderedArtifacts,
            convergence: &convergence
          )
          switch outcome {
          case .rerender:
            if convergence.budgetExceeded {
              break convergenceLoop
            }
            continue convergenceLoop
          case .converged:
            break convergenceLoop
          }
        }
      }

      guard let artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      try applyAcquiredFrame(
        artifacts,
        scheduledFrame: scheduledFrame,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: acquisition,
        hasFrameSink: hasFrameSink,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState

      // Interactive rendering may enqueue more frames while a key or
      // pointer event is already buffered. Yield between committed frames
      // so task/animation invalidations cannot run ahead of user input.
      if eventPump?.hasPendingEvents() == true {
        break
      }
    }
    progressProbe?.record(.schedulerIdle, frameNumber: renderedFrames)
    return nil
  }

  /// Scoped-reuse safety gate. Retained `ViewNode` reuse (enabled via
  /// `TransactionSnapshot.isReuseEquivalent`) needs selective suppression for
  /// runtime state that is intentionally outside `EnvironmentSnapshot` equality
  /// and for active property animations whose registrations must stay fresh:
  ///
  /// 1. **Focus/press moved.** Focus and press are deliberately kept out of
  ///    `EnvironmentSnapshot` equality (see `EnvironmentRuntimeStateTests`), so
  ///    runtime-state readers would reuse stale values unless those readers and
  ///    the old/new controls recompute.
  /// 2. **A property-scope animation is in flight.** A reused subtree's body
  ///    never re-runs, so its `withAnimation`/`repeatForever` is never
  ///    re-registered and `activeAnimationCount` decays to zero. Recomputing
  ///    the active identities each tick keeps the registration alive.
  ///
  /// Identity-agnostic pending animation work still falls back to full
  /// suppression because there is no narrower subtree to name.
  private func retainedReuseSuppressionScopeForFrameSafety()
    -> RetainedReuseSuppressionScope
  {
    var scope = RetainedReuseSuppressionScope()

    let currentFocusIdentity = focusTracker.currentFocusIdentity
    if currentFocusIdentity != previousFrameFocusIdentity {
      scope.formUnion(renderer.runtimeFocusStateDependentIdentities())
      if let previousFrameFocusIdentity {
        scope.insert(previousFrameFocusIdentity)
      }
      if let currentFocusIdentity {
        scope.insert(currentFocusIdentity)
      }
    }

    if pressedIdentity != previousFramePressedIdentity {
      scope.formUnion(renderer.runtimeFocusStateDependentIdentities())
      if let previousFramePressedIdentity {
        scope.insert(previousFramePressedIdentity)
      }
      if let pressedIdentity {
        scope.insert(pressedIdentity)
      }
    }

    let controller = renderer.internalAnimationController
    let activePropertyIdentities = controller.activePropertyAnimationIdentities
    scope.formUnion(activePropertyIdentities)
    if controller.lastTickResult.hasPendingWork,
      activePropertyIdentities.isEmpty
    {
      return .all
    }
    return scope
  }

  private func appendPendingAccessibilityAnnouncements(
    to artifacts: inout FrameArtifacts
  ) {
    let announcements = drainPendingAccessibilityAnnouncements()
    guard !announcements.isEmpty else {
      return
    }
    artifacts.semanticSnapshot.accessibilityAnnouncements.append(contentsOf: announcements)
  }
}
