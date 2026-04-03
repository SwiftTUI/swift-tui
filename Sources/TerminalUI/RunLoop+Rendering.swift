import Core
import View

extension RunLoop {
  package func renderPendingFrames(renderedFrames: inout Int) throws {
    observationBridge.attachInvalidator(scheduler)

    while let scheduledFrame = scheduler.consumeReadyFrame(at: .now()) {
      var rerenderedForFocusSync = false
      while true {
        let artifacts = renderer.render(
          viewBuilder(stateContainer.state, focusTracker.currentFocusIdentity),
          context: resolveContext(for: scheduledFrame),
          proposal: proposal()
        )

        latestSemanticSnapshot = artifacts.semanticSnapshot

        let focusChanged = focusTracker.updateRegions(artifacts.semanticSnapshot.focusRegions)
        let desiredFocusRequest = localFocusBindingRegistry.desiredFocusRequest(
          allowedIdentities: Set(artifacts.semanticSnapshot.focusRegions.map(\.identity))
        )
        let appliedFocusRequest = applyDesiredFocusRequest(desiredFocusRequest)
        let focusStateChanged = localFocusBindingRegistry.sync(
          actualFocusedIdentity: focusTracker.currentFocusIdentity
        )
        let resolvedFocusedValues = localFocusedValuesRegistry.focusedValues(
          for: focusTracker.currentFocusIdentity,
          in: artifacts.resolvedTree
        )
        let focusedValuesChanged = resolvedFocusedValues != currentFocusedValues
        if focusedValuesChanged {
          currentFocusedValues = resolvedFocusedValues
        }

        if focusChanged || appliedFocusRequest || focusStateChanged || focusedValuesChanged {
          rerenderedForFocusSync = true
          continue
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

        break
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
    let registrations = runtimeRegistrations
    registrations.resetAll()

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
