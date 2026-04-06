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

    while let scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      let causeSummary = scheduledFrame.causes
        .map(\.rawValue)
        .sorted()
        .joined(separator: "+")
      var rerenderedForFocusSync = false
      var focusSyncBudget = FocusSyncRerenderBudget()
      var focusSyncBudgetExceeded = false
      var artifacts: FrameArtifacts?
      while true {
        let renderedArtifacts = renderer.render(
          viewBuilder(
            (
              state: stateContainer.state,
              focusedIdentity: focusTracker.currentFocusIdentity
            )),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal()
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
        assertionFailure(
          "Focus synchronization did not converge after \(focusSyncBudget.rerenderCount) rerenders for frame causes \(causeSummary). The runtime will present the latest available tree and continue."
        )
      }

      let presentationDamage: PresentationDamage? =
        if rerenderedForFocusSync {
          nil
        } else {
          artifacts.presentationDamage
        }
      if let damageAwareHost = terminalHost as? any DamageAwareTerminalHosting {
        try damageAwareHost.present(
          artifacts.rasterSurface,
          damage: presentationDamage
        )
      } else {
        try terminalHost.present(artifacts.rasterSurface)
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
      observationBridge.prune(
        keeping: renderer.liveIdentitySnapshot()
      )
      renderedFrames += 1

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
    effectiveEnvironmentValues.themeOverride = terminalHost.theme
    effectiveEnvironmentValues.terminalSize = terminalHost.surfaceSize
    effectiveEnvironmentValues.terminalCellPixelSize =
      terminalHost.graphicsCapabilities.cellPixelSize ?? .init(width: 8, height: 16)
    effectiveEnvironmentValues.focusedIdentity = focusTracker.currentFocusIdentity
    effectiveEnvironmentValues.focusedValues = currentFocusedValues
    effectiveEnvironmentValues.pressedIdentity = pressedIdentity
    if effectiveEnvironmentValues.openLinkAction.isPlaceholder {
      effectiveEnvironmentValues.openLinkAction = systemOpenLinkAction()
    }
    var context = ResolveContext(
      identity: rootIdentity,
      environment: environment,
      environmentValues: effectiveEnvironmentValues,
      transaction: .init(debugSignature: causeSummary),
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
