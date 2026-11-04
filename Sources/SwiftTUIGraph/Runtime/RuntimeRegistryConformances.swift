// Every runtime registry's RuntimeRegistry lifecycle wiring, in one place.
//
// Each conformance maps the uniform lifecycle contract onto the registry's
// domain-specific API: kind-specific restore parameters (owners, ordinals,
// hover recency, gesture pairing) dissolve into the shared contexts, and the
// publication-oracle fingerprint projection lives next to the family list it
// projects. Registries keep their bespoke teardown semantics — the gesture
// registries preserve mid-interaction state, scroll keeps its reveal anchors —
// behind the uniform entry points; see each registry for those invariants.

extension LocalActionRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .action }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(
      handlers.action.registrations,
      ownersByIdentity: handlers.action.owners
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for identity in snapshot().keys {
      builder.add(.action, .identity(identity))
    }
  }
}

extension LocalKeyHandlerRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .keyHandler }

  // The legacy KeyEvent generation used to carry this check alone (key-press
  // handlers were absent at parity with the pre-unification fan-out). With
  // that generation removed, its blocking population — the interactive
  // controls' key handlers — lives in the key-press generation, so the
  // check follows it: dropping a frame out from under an installed key
  // handler stays ineligible.
  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshotKeyPressHandlers().isEmpty && snapshotPasteHandlers().isEmpty
      ? nil
      : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restoreKeyPressHandlers(
      handlers.keyHandler.keyPress.handlers,
      ownersByIdentity: handlers.keyHandler.keyPress.owners,
      ordinalsByIdentity: handlers.keyHandler.keyPress.ordinals
    )
    restorePasteHandlers(
      handlers.keyHandler.paste.handlers,
      ownersByIdentity: handlers.keyHandler.paste.owners,
      ordinalsByIdentity: handlers.keyHandler.paste.ordinals
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for (identity, handlers) in snapshotKeyPressHandlers() {
      builder.add(.keyPress, .identity(identity), count: handlers.count)
    }
    for (identity, handlers) in snapshotPasteHandlers() {
      builder.add(.paste, .identity(identity), count: handlers.count)
    }
  }
}

extension LocalTerminationRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .termination }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(
      handlers.termination.handlers,
      ownersByIdentity: handlers.termination.owners
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for (identity, handlers) in snapshot() {
      builder.add(.termination, .identity(identity), count: handlers.count)
    }
  }
}

extension LocalPointerHandlerRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .pointerHandler }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty && snapshotHover().isEmpty && snapshotWheel().isEmpty
      ? nil
      : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset(preservingRouteHandlersFor: context.preservedGestureIdentities)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(
      rootedAt: roots,
      preserving: context.preservedGestureIdentities
    )
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    let registrations = handlers.pointer.handlers.filter { routeID, _ in
      // Pairing (not exact) lookup: the live gesture handler may have
      // re-registered under a re-minted owner, and the recorded routeID's
      // stale owner must still recognize it and skip the stale restore.
      !(context.activeGestureIdentities.contains(routeID.identity)
        && hasHandler(pairingWith: routeID))
    }
    restore(
      registrations,
      ownersByRouteID: handlers.pointer.handlerOwners,
      structuralRoutes: handlers.pointer.structuralRoutes,
      recency: context.recency
    )
    restoreHover(
      handlers.pointer.hoverHandlers,
      ownersByRouteID: handlers.pointer.hoverOwners,
      recency: context.recency
    )
    restoreWheel(
      handlers.pointer.wheelHandlers,
      ownersByRouteID: handlers.pointer.wheelOwners,
      recency: context.recency
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for routeID in snapshot().keys {
      builder.add(.pointer, .route(routeID.pairingKey))
    }
    for routeID in snapshotHover().keys {
      builder.add(.hover, .route(routeID.pairingKey))
    }
    for routeID in snapshotWheel().keys {
      builder.add(.wheel, .route(routeID.pairingKey))
    }
  }
}

extension LocalGestureRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .gesture }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(
      rootedAt: roots,
      preserving: context.preservedGestureIdentities
    )
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(
      handlers.gesture.recognizers,
      ownersByIdentity: handlers.gesture.owners
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for identity in snapshot().keys {
      builder.add(.gesture, .identity(identity))
    }
  }
}

extension LocalGestureStateRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .gestureState }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(
      rootedAt: roots,
      preserving: context.preservedGestureIdentities
    )
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(
      handlers.gestureState.bindings,
      ownersByIdentity: handlers.gestureState.owners
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for (identity, bindings) in snapshot() {
      builder.add(.gestureState, .identity(identity), count: bindings.count)
    }
  }
}

extension LocalDefaultFocusRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .defaultFocus }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot() == DefaultFocusRegistrationSnapshot() ? nil : .focusBindingSync
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.defaultFocus)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    let snapshot = snapshot()
    for scope in snapshot.scopes {
      builder.add(.defaultFocusScope, .identity(scope.identity))
    }
    for candidate in snapshot.candidates {
      builder.add(.defaultFocusCandidate, .identity(candidate.identity))
    }
  }
}

extension LocalFocusBindingRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .focusBinding }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty && sourceSnapshot().isEmpty ? nil : .focusBindingSync
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeRegistrationsForRepublication(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.focusBinding.registrations)
    restoreSources(handlers.focusBinding.sources)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for source in sourceSnapshot() {
      builder.add(
        .focusBindingSource, .focus(source.domain, source.identity, source.bindingKey))
    }
    for registration in snapshot() {
      builder.add(
        .focusBinding, .focus(registration.domain, registration.identity, registration.bindingKey)
      )
    }
  }
}

extension LocalFocusedValuesRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .focusedValues }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .focusedValueSync
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.focusedValues.registrations)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for registration in snapshot() {
      builder.add(.focusedValues, .identity(registration.identity))
    }
  }
}

extension LocalScrollPositionRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .scrollPosition }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .scrollSync
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.scrollPosition.registrations)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for registration in snapshot() {
      builder.add(.scrollPosition, .identity(registration.identity))
      builder.add(.scrollPositionAxes, .axes(registration.axes))
      builder.add(
        .scrollPositionResolvedOffset, .offset(registration.resolvedOffset))
    }
  }
}

extension LocalLifecycleRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .lifecycle }

  package var isEffectRegistry: Bool {
    true
  }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .lifecycleChange
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.lifecycle)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    let snapshot = snapshot()
    for handlerID in snapshot.appearRegistrations.keys {
      builder.add(.lifecycleAppear, .lifecycle(handlerID))
    }
    for handlerID in snapshot.disappearRegistrations.keys {
      builder.add(.lifecycleDisappear, .lifecycle(handlerID))
    }
    for handlerID in snapshot.changeRegistrations.keys {
      builder.add(.lifecycleChange, .lifecycle(handlerID))
    }
  }
}

extension LocalTaskRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .task }

  package var isEffectRegistry: Bool {
    true
  }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .taskStart
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(
      handlers.task.registrations,
      ownersByIdentity: handlers.task.owners
    )
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for (identity, registrations) in snapshot() {
      builder.add(.task, .identity(identity), count: registrations.count)
    }
  }
}

extension LocalPreferenceObservationRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .preferenceObservation }

  package var isEffectRegistry: Bool {
    true
  }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .preferenceObservationDelta
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.preferenceObservation.registrations)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for registration in snapshot() {
      builder.add(
        .preferenceObservation, .preference(registration.identity, registration.key)
      )
    }
  }
}

extension CommandRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .command }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.command)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for (identity, bindings) in snapshot().keyCommandsByScope {
      builder.add(.command, .identity(identity), count: bindings.count)
    }
  }
}

extension DropDestinationRegistry: RuntimeRegistry {
  package static var kind: RuntimeRegistrationKind { .dropDestination }

  package var activeFrameDropEligibilityBlocker: FrameDropBlocker? {
    snapshot().isEmpty ? nil : .handlerInstallations
  }

  package func reset(context: RuntimeRegistrationLifetimeContext) {
    reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    context: RuntimeRegistrationLifetimeContext
  ) {
    removeSubtrees(rootedAt: roots)
  }

  package func restore(
    from handlers: NodeHandlers,
    context: RuntimeRegistrationRestoreContext
  ) {
    restore(handlers.dropDestination)
  }

  package func fingerprint(into builder: inout RuntimeRegistrationFingerprintBuilder) {
    for identity in snapshot().handlersByScope.keys {
      builder.add(.dropDestination, .identity(identity))
    }
  }
}
