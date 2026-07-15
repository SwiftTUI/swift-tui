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
    registerLiveFocusedValuesProvider()

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    let drainPass = beginDeadlineDrainPass()
    while var scheduledFrame = consumeReadyFrame(for: drainPass) {
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
        applyRenderPassEvaluationPolicy(convergence: convergence)
        let passScheduledFrame =
          convergence.rerenderedForFocusSync
          ? rerenderScheduledFrame(from: scheduledFrame, convergence: convergence)
          : scheduledFrame
        convergence.pendingInvalidationsAtPassStart = schedulerPendingInvalidations()
        let renderedArtifacts = renderer.renderArtifacts(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: passScheduledFrame),
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

  /// Captures the drain-owned deadline cut for one frame-driver pass (the F41
  /// reland guard, report 2026-07-07-008). The scheduler keeps a deadline SET
  /// so later deadlines survive nearer ones — a long-press recognizer's 500 ms
  /// wake is no longer eaten by a 33 ms animation/momentum tick — but survival
  /// alone livelocks the drain on a machine whose per-frame cost meets the
  /// animation cadence: every frame's re-arm is due again by the loop's
  /// re-check. Consuming against a pass-entry cut bounds each drain to the
  /// deadlines armed before it began; deadlines armed during the pass
  /// (animation and momentum re-arms) are withheld — not lost — and the outer
  /// loop's live `hasPendingFrame`/`nextWakeInstant` view re-enters a fresh
  /// pass for them promptly.
  private func beginDeadlineDrainPass() -> (
    scheduler: any DrainPassDeadlineCutting, cut: DeadlineArmCut
  ) {
    // `FrameScheduling` refines `DrainPassDeadlineCutting` (F95), so every
    // injected scheduler carries the cut — there is no ungated consume path
    // for a drain loop to fall back to (the pre-F41 livelock shape).
    (scheduler, scheduler.deadlineArmCut)
  }

  private func consumeReadyFrame(
    for drainPass: (scheduler: any DrainPassDeadlineCutting, cut: DeadlineArmCut)
  ) -> ScheduledFrame? {
    drainPass.scheduler.consumeReadyFrame(
      at: frameReadinessClock(),
      armedBefore: drainPass.cut
    )
  }

  /// Publishes this run loop's `currentFocusedValues` as the live
  /// focused-values source for its graph scope, so imperative callbacks
  /// (key commands, gesture handlers) re-materialize their authoring context
  /// against current focus state instead of their registration-time snapshot.
  private func registerLiveFocusedValuesProvider() {
    LiveFocusedValuesRegistry.register(
      scope: StateGraphScopeID(renderer.viewGraph),
      provider: { [weak self] in
        self?.currentFocusedValues
      }
    )
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
    // A frame was genuinely applied: the pre-start cancel run is broken.
    consecutivePreStartCancelCount = 0
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
    registerLiveFocusedValuesProvider()

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    let drainPass = beginDeadlineDrainPass()
    frameLoop: while var scheduledFrame = consumeReadyFrame(for: drainPass) {
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
        applyRenderPassEvaluationPolicy(convergence: convergence)
        let passScheduledFrame =
          convergence.rerenderedForFocusSync
          ? rerenderScheduledFrame(from: scheduledFrame, convergence: convergence)
          : scheduledFrame
        convergence.pendingInvalidationsAtPassStart = schedulerPendingInvalidations()
        let acquired = await acquireFrameArtifactsAsync(
          scheduledFrame: passScheduledFrame,
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
  /// runtime state that is intentionally outside `EnvironmentSnapshot` equality:
  ///
  /// 1. **Focus/press moved.** Focus and press are deliberately kept out of
  ///    `EnvironmentSnapshot` equality (see `EnvironmentRuntimeStateTests`), so
  ///    runtime-state readers would reuse stale values unless those readers and
  ///    the old/new controls recompute.
  /// Animation deadlines do not enter this scope (F149). The controller owns
  /// active curve state, overlays, and completion drains; a deadline alone
  /// authors no new target value and therefore needs no view-graph evaluation.
  /// Independent input/state/focus/environment causes still contribute their
  /// ordinary dirty work on the same frame.
  ///
  /// Focus/press-only finite scopes are queued as graph-local dirty work by the
  /// frame head. The focus-sync scroll fallback remains root-forced because it
  /// cannot be attributed to an identity cone.
  /// Per-render-pass evaluation policy, shared by both frame drivers and
  /// recomputed PER convergence iteration, not once per scheduled frame: the
  /// eager focus-location rerender runs after a mid-frame relocation
  /// (default-focus adoption, an applied focus request, a focused control's
  /// departure) that a frame-start snapshot cannot have observed —
  /// `previousFrameFocusIdentity` only advances after the frame commits, so
  /// the second pass's scope unions the relocated focus target and its
  /// runtime readers. A stale scope here would let a focus reader outside it
  /// take retained reuse of pre-relocation content.
  ///
  /// The focus-sync rerender itself is selective (F08 lever B): the
  /// relocation cone plus the runtime focus readers already form the pass's
  /// finite suppression scope, the frame head queues that scope as graph-local
  /// dirty work, and the identities the relocation's side effects invalidated
  /// ride the pass's invalidation set (see ``rerenderScheduledFrame``). Two
  /// additions keep it sound:
  ///
  /// - When the previous pass updated `currentFocusedValues`, the
  ///   `@FocusedValue`/`@FocusedBinding` readers must ride this pass's scope:
  ///   the rerender path returns before the converged path's reader
  ///   invalidation, and this pass's convergence check compares against the
  ///   already-updated values — a reader outside the scope would never be
  ///   scheduled again and go permanently stale.
  /// - A scroll-reveal rerender repositions viewport content with no
  ///   attributable identity cone, so it keeps the root-forced fallback.
  ///
  /// Animation deadline-only frames remain eligible for whole-tree retained
  /// reuse and the animation injection stage's zero-computed-node skip.
  private func applyRenderPassEvaluationPolicy(
    convergence: FocusSyncConvergenceState
  ) {
    var suppressionScope = retainedReuseSuppressionScopeForFrame()
    if convergence.rerenderedForFocusSync {
      if convergence.scrollPositionChanged {
        renderer.forceRootEvaluation(source: .focusSyncRerender)
      } else if convergence.focusedValuesChanged {
        suppressionScope.formUnionFocusPresentationMembers(
          renderer.focusedValuesDependentIdentities()
        )
      }
    }
    if !suppressionScope.isEmpty {
      renderer.suppressRetainedReuseForNextFrame(suppressionScope)
    }
  }

  private func retainedReuseSuppressionScopeForFrame()
    -> RetainedReuseSuppressionScope
  {
    var scope = RetainedReuseSuppressionScope()

    let currentFocusIdentity = focusTracker.currentFocusIdentity
    if currentFocusIdentity != previousFrameFocusIdentity {
      let readers = renderer.runtimeFocusStateDependentIdentities()
      scope.formUnionFocusPresentationMembers(readers)
      if let previousFrameFocusIdentity {
        insertFocusMoveMember(previousFrameFocusIdentity, into: &scope)
      }
      if let currentFocusIdentity {
        insertFocusMoveMember(currentFocusIdentity, into: &scope)
      }
      recordSuppressionScopeLegIfTracing(
        leg: "focus-move",
        old: previousFrameFocusIdentity,
        new: currentFocusIdentity,
        readers: readers
      )
    }

    if pressedIdentity != previousFramePressedIdentity {
      let readers = renderer.runtimeFocusStateDependentIdentities()
      scope.formUnionFocusPresentationMembers(readers)
      if let previousFramePressedIdentity {
        insertFocusMoveMember(previousFramePressedIdentity, into: &scope)
      }
      if let pressedIdentity {
        insertFocusMoveMember(pressedIdentity, into: &scope)
      }
      recordSuppressionScopeLegIfTracing(
        leg: "press-move",
        old: previousFramePressedIdentity,
        new: pressedIdentity,
        readers: readers
      )
    }

    return scope
  }

  /// A focus/press move's old/new identity enters the suppression scope as a
  /// FULL member only when its root path carries a runtime-focus side-field
  /// reader (a framework control whose body compares `focusedIdentity` /
  /// `pressedIdentity` against identities at or below itself — `Button`
  /// self-equality, `List` against its rows). A reader-free path means
  /// nothing that resolves there can vary with the move: descendants compare
  /// at-or-below THEMSELVES, containment-bake (`isFocused`) and
  /// `@Environment` wrapper readers ride the wholesale readers union above,
  /// and the focus ring is host-side chrome from the committed semantic
  /// snapshot. Such identities (metadata-only `.focusable()` containers)
  /// become chrome-only members: they certify finite focus/press coverage
  /// for the frame but deny no reuse and queue no dirty work.
  private func insertFocusMoveMember(
    _ identity: Identity,
    into scope: inout RetainedReuseSuppressionScope
  ) {
    if renderer.hasRuntimeFocusReaderOnPath(to: identity) {
      scope.insertFocusPresentationMember(identity)
    } else {
      scope.insertChromeOnlyFocusMember(identity)
      if ReuseDenialTrace.isEnabled {
        ReuseDenialTrace.recordSuppressionScopeDescription(
          "chrome-only(\(identity.path))"
        )
      }
    }
  }

  /// Diagnostic-only (inert unless `SWIFTTUI_REUSE_TRACE`): attributes one
  /// focus/press leg of the frame's retained-reuse suppression scope, so a
  /// broad `suppressed=` count on a transition frame can be traced to the
  /// member whose ancestor/descendant matching produced it (e.g. a near-root
  /// focused container covers its whole subtree).
  private func recordSuppressionScopeLegIfTracing(
    leg: String,
    old: Identity?,
    new: Identity?,
    readers: Set<Identity>
  ) {
    guard ReuseDenialTrace.isEnabled else {
      return
    }
    var description = "\(leg)(old=\(old?.path ?? "nil"),new=\(new?.path ?? "nil")"
    if readers.isEmpty {
      description += ",readers=0)"
    } else {
      let readerPaths = readers.map(\.path).sorted().prefix(8)
      description +=
        ",readers=\(readers.count)[\(readerPaths.joined(separator: "+"))])"
    }
    ReuseDenialTrace.recordSuppressionScopeDescription(description)
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
