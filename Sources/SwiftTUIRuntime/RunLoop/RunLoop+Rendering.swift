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
      advanceScrollMomentumIfNeeded(for: scheduledFrame)
      var convergence = FocusSyncConvergenceState()
      convergence.lifecycleCarryForward = deferredLifecycleCarryForward
      deferredLifecycleCarryForward.removeAll(keepingCapacity: true)

      var artifacts: FrameArtifacts?
      while true {
        // Recomputed PER convergence iteration, not once per scheduled frame:
        // the eager focus-location rerender runs after a mid-frame relocation
        // (default-focus adoption, an applied focus request, scroll-reveal)
        // that a frame-start snapshot cannot have observed —
        // `previousFrameFocusIdentity` only advances after the frame commits,
        // so the second pass's scope unions the relocated focus target and
        // its runtime readers. A stale scope here would let a focus reader
        // outside it take retained reuse of pre-relocation content.
        let retainedReuseFrameSafety = retainedReuseFrameSafetyForFrame()
        let retainedReuseSuppressionScope = retainedReuseFrameSafety.suppressionScope
        if convergence.rerenderedForFocusSync {
          renderer.forceRootEvaluation(source: .focusSyncRerender)
        }
        if retainedReuseFrameSafety.requiresRootEvaluation {
          renderer.forceRootEvaluation(
            source: retainedReuseFrameSafety.rootEvaluationSource ?? .unattributed
          )
        }
        if !retainedReuseSuppressionScope.isEmpty {
          // Focus/press-only finite scopes are queued as graph-local dirty work
          // by the frame head. Animation safety and focus-sync rerenders stay
          // root-forced until their own measurement tranche proves a narrower
          // policy is profitable.
          renderer.suppressRetainedReuseForNextFrame(retainedReuseSuppressionScope)
        }
        let renderedArtifacts = renderer.renderArtifacts(
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
          // The single eager focus-location re-render (capped by
          // `didEagerFocusLocationRerender`) — loop once more, then converge.
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
    reportNewSoundnessProbeViolations()
    mergeLifecycleCarryForward(
      convergence.lifecycleCarryForward,
      into: &artifacts.commitPlan.lifecycle
    )
    appendPendingAccessibilityAnnouncements(to: &artifacts)
    latestSemanticSnapshot = artifacts.semanticSnapshot

    let focusPresentation = artifacts.semanticSnapshot.focusPresentation(
      for: focusTracker.currentFocusIdentity
    )
    let presentationResult = try presentCommittedFrameWithDiagnosticsTiming(
      artifacts,
      damage: presentationDamage(for: artifacts, convergence: convergence),
      hasFrameSink: hasFrameSink
    )
    recordPresentedRasterSurface(artifacts.rasterSurface)
    reportRuntimeIssues(
      lifecycleCoordinator.applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: localLifecycleRegistry,
        currentTaskRegistry: localTaskRegistry
      )
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
      advanceScrollMomentumIfNeeded(for: scheduledFrame)
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
      convergenceLoop: while true {
        // Recomputed PER convergence iteration — see the synchronous driver's
        // twin comment: the eager focus-location rerender follows a mid-frame
        // relocation a frame-start scope snapshot cannot name, and a stale
        // scope would let a focus reader outside it reuse pre-relocation
        // content.
        let retainedReuseFrameSafety = retainedReuseFrameSafetyForFrame()
        let retainedReuseSuppressionScope = retainedReuseFrameSafety.suppressionScope
        if convergence.rerenderedForFocusSync {
          renderer.forceRootEvaluation(source: .focusSyncRerender)
        }
        if retainedReuseFrameSafety.requiresRootEvaluation {
          renderer.forceRootEvaluation(
            source: retainedReuseFrameSafety.rootEvaluationSource ?? .unattributed
          )
        }
        if !retainedReuseSuppressionScope.isEmpty {
          // Focus/press-only finite scopes are queued as graph-local dirty work
          // by the frame head. Animation safety and focus-sync rerenders stay
          // root-forced until their own measurement tranche proves a narrower
          // policy is profitable.
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
          //
          // A skipped frame never commits, so — unlike the committed and elided
          // paths — it does not reschedule the animation deadline. If it was the
          // frame draining an active animation, the live controller still holds
          // that animation but nothing is armed to re-drain it; keep the pump
          // alive so its deferred withAnimation completion still fires.
          requestNextAnimationFrameAfterSkippedFrameIfNeeded()
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
            // The single eager focus-location re-render (capped by
            // `didEagerFocusLocationRerender`) — loop once more, then converge.
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
  ///
  /// The run-loop policy decides separately whether the safety scope also
  /// needs root evaluation: focus/press-only finite scopes are queued as
  /// graph-local dirty work by the frame head, while animation safety stays
  /// root-forced until its own measurement tranche proves a narrower policy
  /// is profitable (the F32 reuse gate already scopes tick-frame recompute).
  private struct RetainedReuseFrameSafety {
    var suppressionScope: RetainedReuseSuppressionScope
    var requiresRootEvaluation: Bool
    var rootEvaluationSource: ForceRootEvaluationSource?
  }

  private func retainedReuseFrameSafetyForFrame()
    -> RetainedReuseFrameSafety
  {
    var scope = RetainedReuseSuppressionScope()
    var requiresRootEvaluation = false
    var rootEvaluationSource: ForceRootEvaluationSource?

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
    if !activePropertyIdentities.isEmpty {
      scope.formUnion(activePropertyIdentities)
      requiresRootEvaluation = true
      rootEvaluationSource = .animationPropertySafety
    }
    if controller.lastTickResult.hasPendingWork,
      activePropertyIdentities.isEmpty
    {
      // Non-property pending work (insertion offsets, matched geometry,
      // removal transitions) is identity-attributable, so suppress reuse for
      // those cones only — subtrees disjoint from the animating identities
      // keep retained/memoized reuse on every tick (F32). Identity-agnostic
      // pending work (stranded empty-batch completion drains) still falls
      // back to full suppression because there is no narrower subtree to
      // name.
      guard
        let attributableIdentities = controller.attributablePendingAnimationIdentities
      else {
        return .init(
          suppressionScope: .all,
          requiresRootEvaluation: true,
          rootEvaluationSource: .identityAgnosticAnimationSafety
        )
      }
      scope.formUnion(attributableIdentities)
      requiresRootEvaluation = true
      rootEvaluationSource = .animationPendingWorkSafety
    }
    return .init(
      suppressionScope: scope,
      requiresRootEvaluation: requiresRootEvaluation,
      rootEvaluationSource: rootEvaluationSource
    )
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
