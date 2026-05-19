// Bulk operations over the runtime registration set.
//
// `RuntimeRegistrationSet.swift` defines the aggregate and how it is
// constructed; this file owns the operations the run loop drives across every
// member registry each frame: full reset, subtree removal, orphaned-gesture
// pruning, restoration from committed node handlers, diagnostics, and
// frame-drop eligibility blockers.
//
// The aggregate's registries are `package` stored properties, so these
// operations move cleanly into an extension without any visibility change.
extension RuntimeRegistrationSet {
  package func resetAll() {
    let preservedGestureIdentities = gestureRegistry?.activeIdentitySnapshot() ?? []

    actionRegistry?.reset()
    keyHandlerRegistry?.reset()
    terminationRegistry?.reset()
    pointerHandlerRegistry?.reset(
      preservingRouteHandlersFor: preservedGestureIdentities
    )
    gestureRegistry?.reset()
    gestureStateRegistry?.reset()
    defaultFocusRegistry?.reset()
    focusBindingRegistry?.reset()
    focusedValuesRegistry?.reset()
    scrollPositionRegistry?.reset()
    lifecycleRegistry?.reset()
    taskRegistry?.reset()
    preferenceObservationRegistry?.reset()
    commandRegistry?.reset()
    dropDestinationRegistry?.reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    let preservedGestureIdentities =
      gestureRegistry?.activeIdentities(rootedAt: roots) ?? []

    actionRegistry?.removeSubtrees(rootedAt: roots)
    keyHandlerRegistry?.removeSubtrees(rootedAt: roots)
    terminationRegistry?.removeSubtrees(rootedAt: roots)
    pointerHandlerRegistry?.removeSubtrees(
      rootedAt: roots,
      preserving: preservedGestureIdentities
    )
    gestureRegistry?.removeSubtrees(
      rootedAt: roots,
      preserving: preservedGestureIdentities
    )
    gestureStateRegistry?.removeSubtrees(
      rootedAt: roots,
      preserving: preservedGestureIdentities
    )
    defaultFocusRegistry?.removeSubtrees(rootedAt: roots)
    focusBindingRegistry?.removeSubtrees(rootedAt: roots)
    focusedValuesRegistry?.removeSubtrees(rootedAt: roots)
    scrollPositionRegistry?.removeSubtrees(rootedAt: roots)
    lifecycleRegistry?.removeSubtrees(rootedAt: roots)
    taskRegistry?.removeSubtrees(rootedAt: roots)
    preferenceObservationRegistry?.removeSubtrees(rootedAt: roots)
    commandRegistry?.removeSubtrees(rootedAt: roots)
    dropDestinationRegistry?.removeSubtrees(rootedAt: roots)
  }

  package func pruneOrphanedGestures(
    keeping liveIdentities: Set<Identity>
  ) {
    gestureRegistry?.prune(keeping: liveIdentities)
    gestureStateRegistry?.prune(keeping: liveIdentities)
  }

  package func restore(
    from handlers: NodeHandlers
  ) {
    let activeGestureIdentities = gestureRegistry?.activeIdentitySnapshot() ?? []
    let pointerHandlerRegistrations =
      handlers.pointerHandlerRegistrations.filter { routeID, _ in
        !(activeGestureIdentities.contains(routeID.identity)
          && (pointerHandlerRegistry?.hasHandler(routeID: routeID) ?? false))
      }
    actionRegistry?.restore(handlers.actionRegistrations)
    keyHandlerRegistry?.restore(handlers.keyHandlerRegistrations)
    keyHandlerRegistry?.restoreKeyPressHandlers(
      handlers.keyPressHandlerRegistrations
    )
    keyHandlerRegistry?.restorePasteHandlers(handlers.pasteHandlerRegistrations)
    terminationRegistry?.restore(handlers.terminationHandlerRegistrations)
    pointerHandlerRegistry?.restore(pointerHandlerRegistrations)
    pointerHandlerRegistry?.restoreHover(handlers.pointerHoverHandlerRegistrations)
    gestureRegistry?.restore(handlers.gestureRegistrations)
    gestureStateRegistry?.restore(handlers.gestureStateRegistrations)
    defaultFocusRegistry?.restore(handlers.defaultFocusRegistrations)
    focusBindingRegistry?.restore(handlers.focusBindingRegistrations)
    focusedValuesRegistry?.restore(handlers.focusedValuesRegistrations)
    scrollPositionRegistry?.restore(handlers.scrollPositionRegistrations)
    lifecycleRegistry?.restore(handlers.lifecycleRegistrations)
    taskRegistry?.restore(handlers.taskRegistrations)
    preferenceObservationRegistry?.restore(
      handlers.preferenceObservationRegistrations
    )
    commandRegistry?.restore(handlers.commandRegistrations)
    dropDestinationRegistry?.restore(handlers.dropDestinationRegistrations)
  }

  package func diagnostics() -> RuntimeRegistrationDiagnostics {
    let gestureStateRegistrations = gestureStateRegistry?.snapshot() ?? [:]
    return RuntimeRegistrationDiagnostics(
      pointerHandlerCount: pointerHandlerRegistry?.snapshot().count ?? 0,
      pointerHoverHandlerCount: pointerHandlerRegistry?.snapshotHover().count ?? 0,
      gestureRecognizerCount: gestureRegistry?.snapshot().count ?? 0,
      gestureStateBindingCount: gestureStateRegistrations.values.reduce(0) { count, bindings in
        count + bindings.count
      }
    )
  }

  package func frameDropEligibilityBlockers() -> Set<FrameDropEligibility.Blocker> {
    var blockers: Set<FrameDropEligibility.Blocker> = []
    if actionRegistry?.snapshot().isEmpty == false
      || keyHandlerRegistry?.snapshot().isEmpty == false
      || keyHandlerRegistry?.snapshotPasteHandlers().isEmpty == false
      || terminationRegistry?.snapshot().isEmpty == false
      || pointerHandlerRegistry?.snapshot().isEmpty == false
      || pointerHandlerRegistry?.snapshotHover().isEmpty == false
      || gestureRegistry?.snapshot().isEmpty == false
      || commandRegistry?.snapshot().isEmpty == false
      || dropDestinationRegistry?.snapshot().isEmpty == false
    {
      blockers.insert(.handlerInstallations)
    }
    if gestureStateRegistry?.snapshot().isEmpty == false {
      blockers.insert(.handlerInstallations)
    }
    if defaultFocusRegistry?.snapshot() != DefaultFocusRegistrationSnapshot() {
      blockers.insert(.focusBindingSync)
    }
    if focusBindingRegistry?.snapshot().isEmpty == false {
      blockers.insert(.focusBindingSync)
    }
    if focusedValuesRegistry?.snapshot().isEmpty == false {
      blockers.insert(.focusedValueSync)
    }
    if scrollPositionRegistry?.snapshot().isEmpty == false {
      blockers.insert(.scrollSync)
    }
    if lifecycleRegistry?.snapshot().isEmpty == false {
      blockers.insert(.lifecycleChange)
    }
    if taskRegistry?.snapshot().isEmpty == false {
      blockers.insert(.taskStart)
    }
    if preferenceObservationRegistry?.snapshot().isEmpty == false {
      blockers.insert(.preferenceObservationDelta)
    }
    return blockers
  }
}
