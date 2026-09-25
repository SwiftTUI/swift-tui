import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  // MARK: - Frame driver (F2: unified sync/async per-frame body, ADR-0021)

  /// Allows short state/focus follow-up chains to settle while guaranteeing
  /// a return to input and termination handling. Periodic state writers can
  /// invalidate faster than frames render; the deadline-arm cut does not
  /// constrain those writes. Count acquisitions, including skipped frames,
  /// so cancellation cannot evade the bound either (STUI-529).
  /// Sixteen acquisitions leave room for the existing two-cancel/two-drop
  /// progress bounds (at most nine acquisitions to a forced commit).
  package static var maxFramesPerDrainPass: Int { 16 }

  /// Synchronous frame driver, retained as a test entry point.
  ///
  /// This driver predates off-screen frame elision and intentionally does not
  /// include an `.elided` arm. Production drives the run loop exclusively
  /// through ``renderPendingFramesAsync(renderedFrames:eventPump:)``, which is
  /// fully wired to the elision gate via `acquireFrameArtifactsAsync`. This
  /// function is only invoked from synchronous test helpers; adding elision
  /// complexity here would serve no production path.
  package func renderPendingFrames(
    renderedFrames: inout Int,
    eventPump: EventPump? = nil,
    appliesWorkBudget: Bool = true
  ) throws {
    guard beginTerminalRenderPassIfAvailable() else {
      return
    }
    defer {
      endTerminalRenderPass()
      reportNewSoundnessProbeViolations()
    }
    // Committed `withAnimation` completions queue during the pass and fire
    // after each frame's lifecycle dispatch (`applyAcquiredFrame`); the
    // pass-end drain is the backstop for paths that throw before it.
    renderer.internalAnimationController.beginDeferringCommittedCompletionDispatch()
    defer {
      let completions =
        renderer.internalAnimationController.endDeferringCommittedCompletionDispatch()
      for completion in completions {
        completion()
      }
    }

    observationBridge.attachInvalidator(scheduler)
    registerLiveFocusedValuesProvider()

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    let drainPass = beginDeadlineDrainPass()
    var consumedScheduledFrames = 0
    var passStartedAt: MonotonicInstant?
    while consumedScheduledFrames < Self.maxFramesPerDrainPass {
      if consumedScheduledFrames > 0,
        shouldYieldDrainPass(
          to: eventPump, passStartedAt: passStartedAt, appliesWorkBudget: appliesWorkBudget)
      {
        break
      }
      processPendingHotReload()
      let consumedAt = frameClock()
      guard var scheduledFrame = consumeReadyFrame(for: drainPass, at: consumedAt) else {
        break
      }
      consumedScheduledFrames += 1
      let passStart = passStartedAt ?? consumedAt
      passStartedAt = passStart
      let ingressAcquisition = ingressAcquisitionSnapshot(
        eventPump: eventPump,
        consumedAt: consumedAt,
        passStartedAt: passStart,
        drainPassFrameIndex: consumedScheduledFrames
      )
      let previousFrameInstant = previousFrameInstant
      let frameInstant = deriveFrameInstant(consumedAt: consumedAt)
      // Transfer-and-clear: everything dispatched before this acquisition is
      // what this frame answers. Inputs arriving during the frame belong to
      // the next one.
      let answeredInputs = takePendingAnsweredInputs()
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

      var geometry: HostGeometryStamp?
      var artifacts: FrameArtifacts?
      while true {
        applyRenderPassEvaluationPolicy(convergence: convergence)
        let passScheduledFrame =
          convergence.rerenderedForFocusSync
          ? rerenderScheduledFrame(from: scheduledFrame, convergence: convergence)
          : scheduledFrame
        convergence.pendingInvalidationsAtPassStart = schedulerPendingInvalidations()
        // `frameInstant` must reach BOTH the resolve context and the render
        // itself. Omitted, the render took `renderArtifacts`' `.now()` default
        // and stamped the frame head — and through it every animation
        // timestamp — with the wall clock, while the async driver passed the
        // frame's instant. So under this driver the injectable `frameClock`
        // never reached animation at all: a pinned-clock test still aged its
        // animations at real speed, and any finite animation whose schedule
        // was shorter than the real cost of the frames around it completed
        // early. That is what purged the removal overlay in
        // `OffscreenFrameElisionRuntimeTests` on slow/loaded machines.
        let hostConfiguration = presentationSurface.hostLayoutConfiguration()
        reconcileHostGeometry(hostConfiguration.geometry)
        geometry = hostConfiguration.geometry
        let renderedArtifacts = renderer.renderArtifacts(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(
            for: passScheduledFrame, frameInstant: frameInstant,
            hostConfiguration: hostConfiguration),
          proposal: proposal(hostConfiguration: hostConfiguration),
          frameInstant: frameInstant
        )
        artifacts = renderedArtifacts
        // This pass COMMITTED — its registration publication just rewrote the
        // live registries. Absorb before the next pass can reset an owner's
        // record without re-registering (an `onChange` that does not re-trigger
        // registers nothing), so a plan folded into the lifecycle
        // carry-forward still finds its closure. Mirrors the async driver's
        // per-pass absorb in `acquireFrameArtifactsAsync`; without it this
        // driver and production disagree about what survives a re-render.
        lifecycleCoordinator.absorbPublishedRegistrations(
          localLifecycleRegistry.snapshot()
        )
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
        consumedAt: consumedAt,
        frameInstant: frameInstant,
        previousFrameInstant: previousFrameInstant,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: FrameAcquisitionState(geometry: geometry),
        ingressAcquisition: ingressAcquisition,
        answeredInputs: answeredInputs,
        hasFrameSink: hasFrameSink,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState
      if terminalHandoffInProgress {
        break
      }
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

  /// Consumes at an instant the caller has already sampled.
  ///
  /// The instant is a parameter rather than a `frameClock()` read in here so
  /// that one frame corresponds to exactly one sample: the caller derives
  /// `frameInstant` from the same reading it consumed with, and every
  /// frame-scoped consumer downstream reads that value. Sampling again inside
  /// the frame would let the readiness decision and the work it admits
  /// disagree about the time — invisibly under the real clock, and
  /// deterministically wrong under a virtual one.
  private func consumeReadyFrame(
    for drainPass: (scheduler: any DrainPassDeadlineCutting, cut: DeadlineArmCut),
    at instant: MonotonicInstant
  ) -> ScheduledFrame? {
    drainPass.scheduler.consumeReadyFrame(
      at: instant,
      armedBefore: drainPass.cut
    )
  }

  /// Hands this frame the inputs dispatched since the previous acquisition
  /// and clears the accumulator, so an input is attributed to exactly one
  /// frame.
  private func takePendingAnsweredInputs() -> AnsweredInputs? {
    let answered = pendingAnsweredInputs
    pendingAnsweredInputs = nil
    return answered
  }

  /// Returns inputs to the accumulator when the frame that took them
  /// presented nothing (skipped tail, off-screen elision). Folding rather
  /// than assigning preserves any input that arrived in the meantime.
  private func restorePendingAnsweredInputs(_ answeredInputs: AnsweredInputs?) {
    pendingAnsweredInputs.fold(answeredInputs)
  }

  /// Whether a drain pass that has already acquired a frame should return to
  /// the outer loop before acquiring another (plan 2026-09-24-001 §4D).
  ///
  /// Two triggers, checked in this order:
  /// - **Input is waiting.** A turn-boundary pull runs first so the check
  ///   sees fresh input from a pulling reader, not only what a stream copy
  ///   task happened to move while the loop was suspended. Interactive
  ///   rendering may enqueue more frames while a key or pointer event is
  ///   already buffered; yielding here keeps task/animation invalidations
  ///   from running ahead of user input. This used to run only after a
  ///   committed async frame; a skipped or elided acquisition spends time
  ///   too, so all three paths reach it now.
  /// - **The elapsed-work budget is spent**, when `drainPassWorkBudget` is
  ///   set: that much frame-clock time since the pass's first acquisition.
  ///   The count bound (`maxFramesPerDrainPass`) is not a wall-time
  ///   responsiveness bound; this one is. It is off by default (see the
  ///   property) and is a measurement knob for the §5 lanes.
  ///
  /// Without an event pump there is no input to serve (manual drivers and
  /// tests), so only the count bound applies. Returning leaves pending
  /// scheduler intent intact; the outer loop re-enters a fresh pass for it.
  private func shouldYieldDrainPass(
    to eventPump: EventPump?,
    passStartedAt: MonotonicInstant?,
    appliesWorkBudget: Bool
  ) -> Bool {
    guard let eventPump else {
      return false
    }
    _ = eventPump.pullInput()
    if eventPump.hasPendingEvents() {
      return true
    }
    guard appliesWorkBudget, let passStartedAt, let workBudget = drainPassWorkBudget else {
      return false
    }
    return passStartedAt.duration(to: frameClock()) >= workBudget
  }

  /// The pump's depth and oldest-entry age, and the acquisition's position in
  /// its drain pass, for the `ingress_*` / `drain_pass_*` columns. Reads the
  /// pump only when a frame sink will report it.
  private func ingressAcquisitionSnapshot(
    eventPump: EventPump?,
    consumedAt: MonotonicInstant,
    passStartedAt: MonotonicInstant,
    drainPassFrameIndex: Int
  ) -> IngressAcquisitionSnapshot {
    guard frameSink != nil else {
      return IngressAcquisitionSnapshot(drainPassFrameIndex: drainPassFrameIndex)
    }
    return IngressAcquisitionSnapshot(
      pumpBatches: eventPump?.pendingBatchCount() ?? 0,
      oldestPendingAge: eventPump?.oldestPendingArrival().map { $0.duration(to: consumedAt) },
      drainPassFrameIndex: drainPassFrameIndex,
      drainPassElapsed: passStartedAt.duration(to: consumedAt)
    )
  }

  /// The instant this frame is *about*: the `frameClock` reading it was
  /// consumed at, made non-decreasing across acquisitions.
  ///
  /// Every kind of frame — deadline, input, invalidation, signal, external —
  /// samples the same host monotonic clock, so animation progress follows
  /// elapsed active time (plan 2026-09-24-001 §4B, STUI-618). A frame that
  /// took 160 ms advances every in-flight animation by about 160 ms at the
  /// next acquisition rather than by the 33 ms its armed deadline nominally
  /// stood for; missed visual samples are skipped, never replayed, so slow
  /// rendering cannot prolong a finite animation and retain its work. The
  /// re-arm chain stays `frameInstant + 33 ms` and is self-correcting: a
  /// deadline armed during a long frame is already overdue when armed, fires
  /// at once, and the next acquisition samples the elapsed time.
  ///
  /// Two earlier rules lived here and both mixed time domains:
  ///
  /// - A deadline-triggered frame animated to its *scheduled* instant. Under
  ///   load the armed chain lagged the clock by a growing amount, so a 1.6 s
  ///   effect needed about 49 rendered ticks however long each one took —
  ///   the counter demo's ripple backlog.
  /// - A non-deadline wake was clamped to the nearest overdue armed deadline
  ///   so it would not jump the lagging chain to the clock in one frame (the
  ///   gallery section 19 spring snap; org tracker T5). That snap arose only
  ///   because the two kinds of frame read different domains; with one
  ///   sampled domain there is no accumulated lag to jump, and
  ///   `AnimationLogicalCompletionAsyncTests` still pins the journey. The
  ///   clamp also pinned animation time to whichever scheduler deadline
  ///   happened to be first — a long-press or momentum timer with nothing to
  ///   do with animation.
  ///
  /// `ScheduledFrame.triggeredDeadline` remains the routing key for
  /// gesture-deadline drains and scroll momentum, which read it separately;
  /// it is no longer a time domain for animation.
  ///
  /// Non-decreasing is guaranteed here rather than assumed of the clock: the
  /// pause-aware production clock is monotonic, but the synchronous driver
  /// and tests can install any closure, and a frame must never animate
  /// backwards relative to the frame before it. Elided and skipped
  /// acquisitions derive their instant here too, so the guarantee covers them.
  private func deriveFrameInstant(
    consumedAt: MonotonicInstant
  ) -> MonotonicInstant {
    let frameInstant =
      if let previousFrameInstant, previousFrameInstant > consumedAt {
        previousFrameInstant
      } else {
        consumedAt
      }
    previousFrameInstant = frameInstant
    return frameInstant
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
    consumedAt: MonotonicInstant,
    frameInstant: MonotonicInstant,
    previousFrameInstant: MonotonicInstant?,
    renderIntentDiagnostics: RenderIntentCoalescingDiagnostics,
    convergence: FocusSyncConvergenceState,
    acquisition: FrameAcquisitionState,
    ingressAcquisition: IngressAcquisitionSnapshot,
    answeredInputs: AnsweredInputs?,
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
    let scrollTranslation = scrollTranslation(
      for: artifacts,
      frameOrdinal: renderedFrames + 1
    )
    appliedHostGeometry = acquisition.geometry
    let presentationResult = try presentCommittedFrameWithDiagnosticsTiming(
      artifacts,
      damage: presentationDamage(for: artifacts, convergence: convergence),
      geometry: acquisition.geometry,
      translationCandidate: presentationScrollTranslationCandidate(
        committed: artifacts.committedScrollTranslation,
        presentTime: scrollTranslation.candidate,
        frameOrdinal: renderedFrames + 1
      ),
      hasFrameSink: hasFrameSink,
      frameOrdinal: renderedFrames + 1
    )
    recordPresentedRasterSurface(artifacts.rasterSurface)
    previousPresentedScrollLedger = scrollTranslation.ledger
    reportRuntimeIssues(
      lifecycleCoordinator.applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: localLifecycleRegistry,
        currentTaskRegistry: localTaskRegistry
      )
    )
    // AFTER the lifecycle dispatch, so a completion's state writes get their
    // own resolve before any same-frame `onChange` can read them (the stuck-
    // ripple absorbing state), and BEFORE `flushPostActionInvalidations` so
    // the writes' invalidations flow into this frame's flush as they did
    // when completions fired at commit.
    fireDeferredAnimationCompletions()
    hotReloadSession?.finishCommittedReplay()
    acknowledgeHotReloadCommit()
    updateFocusPresentation(focusPresentation)
    // Record the committed focus so the next frame's reuse-safety gate can
    // detect a focus move (see ``retainedReuseSuppressionScopeForFrameSafety()``).
    previousFrameFocusIdentity = focusTracker.currentFocusIdentity
    previousFramePressedIdentity = pressedIdentity
    // The committed frame reflected every pending focus move; endpoints
    // deferred by the narrowing filter are spent. (Superseded frames do not
    // reach here, so their replays keep re-deriving the same contribution.)
    focusTrackerInvalidationFilter?.clearPendingMoveEndpoints()
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
    requestNextAnimationFrameIfNeeded(animationTick, at: frameInstant)
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

    // Cost includes acquisition and synchronous commit/present submission,
    // but never waits for the terminal writer queue's delivery acknowledgment.
    if let recorder = scheduler as? any CommittedFrameCostRecording,
      recorder.mergePressurePacingEnabled || hasFrameSink
    {
      let acknowledgedAt = frameClock()
      recorder.recordCommittedFrame(
        cost: consumedAt.duration(to: acknowledgedAt), at: acknowledgedAt)
    }
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
      answeredInputs: answeredInputs,
      frameInstant: frameInstant,
      consumedAt: consumedAt,
      previousFrameInstant: previousFrameInstant,
      ingressAcquisition: ingressAcquisition,
      translationCandidate: scrollTranslation.candidate,
      committedTranslation: artifacts.committedScrollTranslation,
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

  /// - Parameters:
  ///   - frameBudget: the acquisition cap for this pass; defaults to
  ///     `maxFramesPerDrainPass`.
  ///   - appliesWorkBudget: whether `drainPassWorkBudget` (when set) bounds
  ///     this pass. The cooperative exit flush passes `false` so a short
  ///     follow-up chain still presents the input handled in its batch before
  ///     exit — there is no further input to serve, so the budget has no
  ///     purpose there.
  package func renderPendingFramesAsync(
    renderedFrames: inout Int,
    eventPump: EventPump?,
    frameBudget: Int? = nil,
    appliesWorkBudget: Bool = true
  ) async throws -> RunLoopExitReason? {
    guard beginTerminalRenderPassIfAvailable() else {
      return nil
    }
    defer {
      endTerminalRenderPass()
      reportNewSoundnessProbeViolations()
    }
    // Committed `withAnimation` completions queue during the pass and fire
    // after each frame's lifecycle dispatch (`applyAcquiredFrame`) or at the
    // elided/skipped branches; the pass-end drain is the backstop for paths
    // that throw before those sites.
    renderer.internalAnimationController.beginDeferringCommittedCompletionDispatch()
    defer {
      let completions =
        renderer.internalAnimationController.endDeferringCommittedCompletionDispatch()
      for completion in completions {
        completion()
      }
    }

    observationBridge.attachInvalidator(scheduler)
    registerLiveFocusedValuesProvider()

    let hasFrameSink = frameSink != nil
    renderer.setElidedFrameTimingDiagnosticsEnabled(
      hasFrameSink || runtimeConfiguration.debug
    )
    let drainPass = beginDeadlineDrainPass()
    let frameBudget = frameBudget ?? Self.maxFramesPerDrainPass
    var consumedScheduledFrames = 0
    var passStartedAt: MonotonicInstant?
    frameLoop: while true {
      if terminalHandoffInProgress {
        break frameLoop
      }
      // Leave unconsumed work in the scheduler for the next pass. Even a
      // cooperative exit flush must return when a periodic producer keeps
      // invalidating during every frame on a slow machine.
      if consumedScheduledFrames >= frameBudget {
        break frameLoop
      }
      // Input service between acquisitions: runs after committed, skipped,
      // and elided acquisitions alike (a frame that presented nothing still
      // spent the time), pulls fresh input first, and also honors the
      // elapsed-work budget.
      if consumedScheduledFrames > 0,
        shouldYieldDrainPass(
          to: eventPump, passStartedAt: passStartedAt, appliesWorkBudget: appliesWorkBudget)
      {
        break frameLoop
      }
      processPendingHotReload()
      let consumedAt = frameClock()
      guard var scheduledFrame = consumeReadyFrame(for: drainPass, at: consumedAt) else {
        break frameLoop
      }
      let previousFrameInstant = previousFrameInstant
      let frameInstant = deriveFrameInstant(consumedAt: consumedAt)
      consumedScheduledFrames += 1
      let passStart = passStartedAt ?? consumedAt
      passStartedAt = passStart
      let ingressAcquisition = ingressAcquisitionSnapshot(
        eventPump: eventPump,
        consumedAt: consumedAt,
        passStartedAt: passStart,
        drainPassFrameIndex: consumedScheduledFrames
      )
      // Transfer-and-clear (see the synchronous driver): this frame answers
      // what was dispatched before its acquisition.
      let answeredInputs = takePendingAnsweredInputs()
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
          frameInstant: frameInstant,
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
          //
          // Nothing was presented, so the inputs this acquisition took over
          // are still unanswered — hand them back to whichever frame does
          // present, exactly like the lifecycle carry-forward above.
          //
          // Earlier convergence passes of this frame DID commit, and their
          // deferred completions must not outlive the frame they rode with.
          fireDeferredAnimationCompletions()
          restorePendingAnsweredInputs(answeredInputs)
          requestNextAnimationFrameAfterSkippedFrameIfNeeded(at: frameInstant)
          continue frameLoop
        case .elided:
          // Off-screen elision fired: `commitElidedFrame` (inside the gate
          // closure) already published the advanced animation state to live
          // and queued its deferred completions, but no tail ran and nothing
          // was presented. Fire the queued completions here (an elided frame
          // dispatches no lifecycle plan, so there is nothing to order them
          // after), keep the animation loop alive by rescheduling the next
          // deadline from the now-live tick result, carry lifecycle forward
          // (no tail consumed it), record the diagnostic, advance the frame
          // counter, and abandon the rest of this frame.
          //
          // An elided frame presents nothing, so — like a skipped one — its
          // answered inputs stay unanswered and carry forward. Reporting them
          // here would claim a latency for pixels that never appeared.
          fireDeferredAnimationCompletions()
          restorePendingAnsweredInputs(answeredInputs)
          appendLifecycleCarryForward(
            convergence.lifecycleCarryForward,
            into: &deferredLifecycleCarryForward
          )
          requestNextAnimationFrameIfNeeded(
            renderer.internalAnimationController.lastTickResult,
            at: frameInstant
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
        case .rendered(let renderedArtifacts, let tailJobState, let dropDecision, let geometry):
          acquisition.geometry = geometry
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
        consumedAt: consumedAt,
        frameInstant: frameInstant,
        previousFrameInstant: previousFrameInstant,
        renderIntentDiagnostics: renderIntentDiagnostics,
        convergence: convergence,
        acquisition: acquisition,
        ingressAcquisition: ingressAcquisition,
        answeredInputs: answeredInputs,
        hasFrameSink: hasFrameSink,
        renderedFrames: &renderedFrames
      )
      previousRenderedState = currentState
      // The pending-input yield that used to sit here runs at the top of the
      // loop, so skipped and elided acquisitions are covered too.
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

  /// The pass's invalidation identities under focus-move narrowing
  /// (plan 2026-08-12-001 Stage 2): the scheduled frame's identities — which
  /// hold only non-focus sources while narrowing defers tracker notifications
  /// — plus every pending focus-move endpoint that still warrants a recompute
  /// cone NOW, re-validated against the live registries exactly like the
  /// suppression-scope legs (`insertFocusMoveMember`): an endpoint whose root
  /// path carries a runtime-focus reader and that declared no
  /// focus-presentation-inert slots. A departed endpoint fails the reader
  /// check (its path has no live readers) and contributes nothing — where the
  /// event-time enqueue carried its unmappable identity into the pass and the
  /// reuse door's conservative nearest-live-ancestor remap conflict-denied
  /// the whole tree (the measured palette-close cone).
  func focusNarrowedInvalidationIdentities(
    for scheduledFrame: ScheduledFrame
  ) -> Set<Identity> {
    guard FocusMoveInvalidationNarrowing.isEnabled,
      let filter = focusTrackerInvalidationFilter,
      !filter.pendingMoveEndpointsSinceLastCommit.isEmpty
    else {
      return scheduledFrame.invalidatedIdentities
    }
    var identities = scheduledFrame.invalidatedIdentities
    var kept = 0
    for endpoint in filter.pendingMoveEndpointsSinceLastCommit {
      if !renderer.hasFocusPresentationInertSlots(for: endpoint),
        renderer.hasRuntimeFocusReaderOnPath(to: endpoint)
      {
        identities.insert(endpoint)
        kept += 1
      }
    }
    if ReuseDenialTrace.isEnabled {
      let dropped = filter.pendingMoveEndpointsSinceLastCommit.count - kept
      ReuseDenialTrace.recordSuppressionScopeDescription(
        "focus-move-narrowing(kept=\(kept),dropped=\(dropped))"
      )
    }
    return identities
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
