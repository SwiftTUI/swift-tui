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
  private enum AnimationWakeTiming {
    // When a frame overruns its nominal 33 ms budget, the controller's
    // requested deadline can already be in the past by the time the
    // run loop reaches the scheduling site below. Re-queuing an already
    // due deadline would make `renderPendingFrames` spin inside the same
    // call; failing to schedule anything would stall the animation until
    // unrelated input arrives. Clamp overdue deadlines slightly into the
    // future so the next tick runs "as soon as possible" on the next
    // event-loop turn without busy-looping in-place.
    static var minimumLeadTime: Duration { .milliseconds(1) }
  }

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
        latestActivePaletteCommands =
          commandRegistry
          .paletteCommands(along: currentFocusScopePath())
          .map { command in
            ActivePaletteCommand(
              name: command.name,
              description: command.description,
              isEnabled: command.isEnabled,
              action: command.action
            )
          }
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
      if animationTick.hasPendingWork,
        let nextDeadline = animationTick.nextDeadline
      {
        let now = MonotonicInstant.now()
        let scheduledDeadline =
          if nextDeadline > now {
            nextDeadline
          } else {
            now.advanced(by: AnimationWakeTiming.minimumLeadTime)
          }
        scheduler.requestDeadline(scheduledDeadline)
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
    effectiveEnvironmentValues.activePaletteCommands = latestActivePaletteCommands
    if effectiveEnvironmentValues.openLinkAction.isPlaceholder {
      effectiveEnvironmentValues.openLinkAction = systemOpenLinkAction()
    }
    var transactionSnapshot = TransactionSnapshot(debugSignature: causeSummary)
    transactionSnapshot.animationRequest = scheduledFrame.animationRequest
    transactionSnapshot.animationBatchID = scheduledFrame.animationBatchID
    // Phase 3's ``diffAndEnqueue`` retargets in-flight animations
    // correctly via ``sample(existing, at:)`` + ``effectiveFrom``, so
    // the previous re-injection of the controller's "dominant active
    // request" on tick frames is no longer required.  A `.inherit`
    // tick frame whose resolve diffs an unchanged property won't
    // touch the running animation (the diff bails on ``previous ==
    // current``); a tick frame whose resolve diffs a CHANGED property
    // under `.inherit` correctly purges the obsolete animation, which
    // matches SwiftUI's "untracked write snaps" semantics.  The
    // scheduler stays animation-unaware; all retarget state lives on
    // the controller.
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
    context.commandRegistry = commandRegistry
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
