import Core
import View

package struct FocusSyncRerenderBudget: Equatable, Sendable {
  package let maximumRerenders: Int
  package private(set) var rerenderCount: Int

  package init(maximumRerenders: Int = 16) {
    precondition(maximumRerenders > 0)
    self.maximumRerenders = maximumRerenders
    rerenderCount = 0
  }

  /// Returns `true` when another focus-sync rerender is still allowed.
  package mutating func recordRerender() -> Bool {
    rerenderCount += 1
    return rerenderCount < maximumRerenders
  }
}

extension RunLoop {
  package func renderPendingFrames(renderedFrames: inout Int) throws {
    observationBridge.attachInvalidator(scheduler)

    let hasDiagnosticsLogger = diagnosticsLogger != nil
    while let scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      var rerenderedForFocusSync = false
      var focusSyncBudget = FocusSyncRerenderBudget()
      var focusSyncBudgetExceeded = false
      var artifacts: FrameArtifacts?
      let currentState = stateContainer.state
      if previousRenderedState != currentState {
        renderer.forceRootEvaluation()
        previousRenderedState = currentState
      }
      while true {
        if rerenderedForFocusSync {
          renderer.forceRootEvaluation()
        }
        let renderedArtifacts = renderer.render(
          viewBuilder(
            (
              state: currentState,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal(),
          collectsDiagnostics: hasDiagnosticsLogger
        )
        artifacts = renderedArtifacts

        latestSemanticSnapshot = renderedArtifacts.semanticSnapshot

        let focusChanged = focusTracker.updateRegions(
          renderedArtifacts.semanticSnapshot.focusRegions)
        let desiredFocusRequest = localFocusBindingRegistry.desiredFocusRequest(
          allowedIdentities: Set(renderedArtifacts.semanticSnapshot.focusRegions.map(\.identity))
        )
        let appliedFocusRequest = applyDesiredFocusRequest(desiredFocusRequest)
        let focusStateChanged = localFocusBindingRegistry.sync(
          actualFocusedIdentity: focusTracker.currentFocusIdentity
        )
        let resolvedFocusedValues = localFocusedValuesRegistry.focusedValues(
          for: focusTracker.currentFocusIdentity,
          in: renderedArtifacts.resolvedTree
        )
        let focusedValuesChanged = resolvedFocusedValues != currentFocusedValues
        if focusedValuesChanged {
          currentFocusedValues = resolvedFocusedValues
        }

        if focusChanged || appliedFocusRequest || focusStateChanged || focusedValuesChanged {
          rerenderedForFocusSync = true
          if !focusSyncBudget.recordRerender() {
            focusSyncBudgetExceeded = true
            break
          }
          continue
        }
        break
      }

      guard let artifacts else {
        preconditionFailure("Focus synchronization produced no frame artifacts.")
      }
      if focusSyncBudgetExceeded {
        let causes = scheduledFrame.causes.map(\.rawValue).sorted().joined(separator: "+")
        assertionFailure(
          "Focus synchronization did not converge after \(focusSyncBudget.rerenderCount) rerenders for frame causes \(causes). The runtime will present the latest available tree and continue."
        )
      }

      let presentationDamage: PresentationDamage? =
        if rerenderedForFocusSync {
          nil
        } else {
          artifacts.presentationDamage
        }
      var presentationMetrics = TerminalPresentationMetrics()
      let presentStart: ContinuousClock.Instant?
      let presentClock: ContinuousClock?
      if hasDiagnosticsLogger {
        let clock = ContinuousClock()
        presentClock = clock
        presentStart = clock.now
      } else {
        presentClock = nil
        presentStart = nil
      }
      if let damageAwareHost = terminalHost as? any DamageAwareTerminalHosting {
        presentationMetrics = try damageAwareHost.present(
          artifacts.rasterSurface,
          damage: presentationDamage
        )
      } else {
        presentationMetrics = try terminalHost.present(artifacts.rasterSurface)
      }
      let presentationDuration: Duration =
        if let presentStart, let presentClock {
          presentStart.duration(to: presentClock.now)
        } else {
          .zero
        }
      lifecycleCoordinator.applyCommittedFrame(
        plan: artifacts.commitPlan,
        currentLifecycleRegistry: localLifecycleRegistry,
        currentTaskRegistry: localTaskRegistry
      )
      _ = localPreferenceObservationRegistry.applyChanges(
        since: previousPreferenceObservations
      )
      previousPreferenceObservations = localPreferenceObservationRegistry.snapshot()
      if !postActionInvalidationIdentities.isEmpty {
        scheduler.requestInvalidation(of: postActionInvalidationIdentities)
        postActionInvalidationIdentities.removeAll(keepingCapacity: true)
      }
      // After rendering, request the next animation frame deadline if
      // any animations are still in flight AND at least one of the
      // identities affected by the tick is geometrically visible in
      // this frame's rasterized output.  Skipping the deadline when
      // every affected identity is clipped (e.g. ``ScrollView`` content
      // below the viewport, or an inactive ``TabView`` tab) quiesces
      // the tick loop so we don't burn CPU driving an animation into
      // a subtree that produces zero visible cells.  The animation
      // itself stays live on the controller; when any external
      // invalidation wakes the scheduler — scroll, resize, tab
      // switch, state change — the next frame's visibility check
      // re-runs and, if the affected identity is now in
      // ``drawnIdentities``, the tick loop resumes.
      //
      // This is a geometric predicate, not an observational one: we
      // do NOT skip the deadline just because ``presentationDamage``
      // happened to come out empty for one coincidental frame.  That
      // would be a one-way trap — the only thing that could restart
      // the loop is the next tick's damage, which requires a tick to
      // find out.  Identity-in-viewport is a stable invariant that
      // flips only when layout, clip, or state changes, and each of
      // those paths already invalidates the scheduler.
      let animationTick = renderer.internalAnimationController.lastTickResult
      if animationTick.hasActiveAnimations,
        let nextDeadline = animationTick.nextDeadline
      {
        let anyAffectedIdentityVisible = !animationTick.affectedIdentities
          .isDisjoint(with: artifacts.drawnIdentities)
        if anyAffectedIdentityVisible {
          scheduler.requestDeadline(nextDeadline)
        }
      }
      observationBridge.prune(
        keeping: renderer.liveIdentitySnapshot()
      )
      renderedFrames += 1

      if let diagnosticsLogger {
        let diag = artifacts.diagnostics
        let cacheMetrics = diag.measurementCache
        let cacheHitRate: Double? =
          if let cacheMetrics, cacheMetrics.lookups > 0 {
            Double(cacheMetrics.hits) / Double(cacheMetrics.lookups)
          } else {
            nil
          }
        let pipelineTotal = diag.phaseTimings?.total ?? .zero
        let causeSummary = scheduledFrame.causes
          .map(\.rawValue)
          .sorted()
          .joined(separator: "+")
        diagnosticsLogger.log(
          FrameDiagnosticRecord(
            frameNumber: renderedFrames,
            causeSummary: causeSummary,
            focusSyncRerenders: focusSyncBudget.rerenderCount,
            invalidatedIdentityCount: diag.invalidatedIdentities.count,
            resolvedNodeCount: diag.resolvedNodeCount,
            resolvedNodesComputed: diag.resolvedNodesComputed,
            resolvedNodesReused: diag.resolvedNodesReused,
            measuredNodeCount: diag.measuredNodeCount,
            measuredNodesComputed: diag.measuredNodesComputed,
            measuredNodesReused: diag.measuredNodesReused,
            placedNodeCount: diag.placedNodeCount,
            drawNodeCount: diag.drawNodeCount,
            interactionRegionCount: diag.interactionRegionCount,
            focusRegionCount: diag.focusRegionCount,
            phaseTimings: diag.phaseTimings,
            presentationStrategy: presentationMetrics.strategy == .fullRepaint
              ? "full" : "incremental",
            presentationBytesWritten: presentationMetrics.bytesWritten,
            presentationLinesTouched: presentationMetrics.linesTouched,
            presentationCellsChanged: presentationMetrics.cellsChanged,
            presentationDuration: presentationDuration,
            damageRowCount: presentationDamage.map(\.dirtyRows.count),
            measurementCacheHitRate: cacheHitRate,
            totalFrameDuration: pipelineTotal + presentationDuration
          )
        )
      }

      if let transientPressedIdentity,
        transientPressedIdentity == pressedIdentity
      {
        self.transientPressedIdentity = nil
        setPressedIdentity(nil, transient: false)
      }
    }
  }

  package func applyDesiredFocusRequest(
    _ request: FocusBindingRequest
  ) -> Bool {
    switch request {
    case .none:
      return false
    case .clear:
      return focusTracker.clearFocus()
    case .focus(let identity):
      return focusTracker.setFocus(to: identity)
    }
  }

  package func resolveContext(
    for scheduledFrame: ScheduledFrame
  ) -> ResolveContext {
    let causeSummary = scheduledFrame.causes
      .map(\.rawValue)
      .sorted()
      .joined(separator: "+")
    var effectiveEnvironmentValues = environmentValues
    effectiveEnvironmentValues.terminalAppearance = terminalHost.appearance
    effectiveEnvironmentValues.theme = terminalHost.theme
    effectiveEnvironmentValues.terminalSize = terminalHost.surfaceSize
    effectiveEnvironmentValues.terminalCellPixelSize =
      terminalHost.graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)
    effectiveEnvironmentValues.focusedIdentity = focusTracker.currentFocusIdentity
    effectiveEnvironmentValues.focusedValues = currentFocusedValues
    effectiveEnvironmentValues.pressedIdentity = pressedIdentity
    if effectiveEnvironmentValues.openLinkAction.isPlaceholder {
      effectiveEnvironmentValues.openLinkAction = systemOpenLinkAction()
    }
    var transactionSnapshot = TransactionSnapshot(debugSignature: causeSummary)
    transactionSnapshot.animationRequest = scheduledFrame.animationRequest
    transactionSnapshot.animationBatchID = scheduledFrame.animationBatchID
    // If the scheduled frame carries no explicit animation intent —
    // typically a tick frame or a background-observable wake — but
    // the animation controller has animations in flight, inject its
    // dominant active request.  This keeps any value-change diffs
    // that happen during this resolve from snapping the in-flight
    // animation: they retarget instead.  The scheduler itself stays
    // animation-unaware; all the state lives on the controller.
    if transactionSnapshot.animationRequest == .inherit,
      let active = renderer.internalAnimationController.dominantActiveRequest()
    {
      transactionSnapshot.animationRequest = active
    }
    var context = ResolveContext(
      identity: rootIdentity,
      environment: environment,
      environmentValues: effectiveEnvironmentValues,
      transaction: transactionSnapshot,
      invalidatedIdentities: scheduledFrame.invalidatedIdentities,
      localActionRegistry: localActionRegistry,
      localKeyHandlerRegistry: localKeyHandlerRegistry,
      localLifecycleRegistry: localLifecycleRegistry,
      localTaskRegistry: localTaskRegistry,
      applyEnvironmentValues: true
    )
    context.localPointerHandlerRegistry = localPointerHandlerRegistry
    context.localFocusBindingRegistry = localFocusBindingRegistry
    context.localFocusedValuesRegistry = localFocusedValuesRegistry
    context.localPreferenceObservationRegistry = localPreferenceObservationRegistry
    context.hotkeyRegistry = hotkeyRegistry
    context.invalidationProxy = .init(invalidator: scheduler)
    context.observationBridge = observationBridge
    return context
  }

  package func proposal() -> ProposedSize {
    if let proposalOverride {
      return proposalOverride
    }

    let size = terminalHost.surfaceSize
    return .init(width: size.width, height: size.height)
  }
}
