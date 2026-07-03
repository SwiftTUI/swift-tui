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

  /// After a scoped `.subtrees` restore, re-sorts the only registries whose
  /// cross-node restore order is observable — the global append-ordered focus
  /// lists — into canonical identity order, so the result is byte-identical to
  /// a full rebuild. The dict/route-keyed registries are order-independent, and
  /// the per-identity handler lists (key/termination) come from a single node
  /// each (their within-identity order is preserved by the scoped restore and
  /// their cross-identity dispatch order is determined by the focus/identity
  /// path at dispatch time, not restore order), so none of those need this.
  package func normalizeScopedRestoreOrder() {
    defaultFocusRegistry?.normalizeOrderByIdentity()
    focusBindingRegistry?.normalizeOrderByIdentity()
  }

  package func pruneOrphanedGestures(
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    gestureRegistry?.prune(keeping: liveNodeIDs)
    gestureStateRegistry?.prune(keeping: liveNodeIDs)
  }

  package func restore(
    from handlers: NodeHandlers,
    recency: UInt64 = 0
  ) {
    let activeGestureIdentities = gestureRegistry?.activeIdentitySnapshot() ?? []
    let pointerHandlerRegistrations =
      handlers.pointerHandlerRegistrations.filter { routeID, _ in
        // Pairing (not exact) lookup: the live gesture handler may have
        // re-registered under a re-minted owner, and the recorded routeID's
        // stale owner must still recognize it and skip the stale restore.
        !(activeGestureIdentities.contains(routeID.identity)
          && (pointerHandlerRegistry?.hasHandler(pairingWith: routeID) ?? false))
      }
    actionRegistry?.restore(
      handlers.actionRegistrations,
      ownersByIdentity: handlers.actionRegistrationOwners
    )
    keyHandlerRegistry?.restore(
      handlers.keyHandlerRegistrations,
      ownersByIdentity: handlers.keyHandlerRegistrationOwners
    )
    keyHandlerRegistry?.restoreKeyPressHandlers(
      handlers.keyPressHandlerRegistrations,
      ownersByIdentity: handlers.keyPressHandlerRegistrationOwners,
      ordinalsByIdentity: handlers.keyPressHandlerRegistrationOrdinals
    )
    keyHandlerRegistry?.restorePasteHandlers(
      handlers.pasteHandlerRegistrations,
      ownersByIdentity: handlers.pasteHandlerRegistrationOwners,
      ordinalsByIdentity: handlers.pasteHandlerRegistrationOrdinals
    )
    terminationRegistry?.restore(
      handlers.terminationHandlerRegistrations,
      ownersByIdentity: handlers.terminationHandlerRegistrationOwners
    )
    pointerHandlerRegistry?.restore(
      pointerHandlerRegistrations,
      ownersByRouteID: handlers.pointerHandlerRegistrationOwners
    )
    pointerHandlerRegistry?.restoreHover(
      handlers.pointerHoverHandlerRegistrations,
      ownersByRouteID: handlers.pointerHoverHandlerRegistrationOwners,
      recency: recency
    )
    gestureRegistry?.restore(
      handlers.gestureRegistrations,
      ownersByIdentity: handlers.gestureRegistrationOwners
    )
    gestureStateRegistry?.restore(
      handlers.gestureStateRegistrations,
      ownersByIdentity: handlers.gestureStateRegistrationOwners
    )
    defaultFocusRegistry?.restore(handlers.defaultFocusRegistrations)
    focusBindingRegistry?.restore(handlers.focusBindingRegistrations)
    focusedValuesRegistry?.restore(handlers.focusedValuesRegistrations)
    scrollPositionRegistry?.restore(handlers.scrollPositionRegistrations)
    lifecycleRegistry?.restore(handlers.lifecycleRegistrations)
    taskRegistry?.restore(
      handlers.taskRegistrations,
      ownersByIdentity: handlers.taskRegistrationOwners
    )
    preferenceObservationRegistry?.restore(
      handlers.preferenceObservationRegistrations
    )
    commandRegistry?.restore(handlers.commandRegistrations)
    dropDestinationRegistry?.restore(handlers.dropDestinationRegistrations)
  }

  /// Restores ONLY lifecycle, task, and preference-observation registrations
  /// from a node's handlers. Used by the always-full effect-registration
  /// republication that runs even on scoped-publication frames, so handlers on
  /// a capture-hosted, viewport-activated, or otherwise reused node are
  /// available when the runtime applies side effects for that node.
  package func restoreEffectRegistrations(from handlers: NodeHandlers) {
    lifecycleRegistry?.restore(handlers.lifecycleRegistrations)
    taskRegistry?.restore(
      handlers.taskRegistrations,
      ownersByIdentity: handlers.taskRegistrationOwners
    )
    preferenceObservationRegistry?.restore(
      handlers.preferenceObservationRegistrations
    )
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
