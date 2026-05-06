public struct RuntimeRegistrationDiagnostics: Equatable, Sendable {
  public var pointerHandlerCount: Int
  public var pointerHoverHandlerCount: Int
  public var gestureRecognizerCount: Int
  public var gestureStateBindingCount: Int

  public init(
    pointerHandlerCount: Int = 0,
    pointerHoverHandlerCount: Int = 0,
    gestureRecognizerCount: Int = 0,
    gestureStateBindingCount: Int = 0
  ) {
    self.pointerHandlerCount = pointerHandlerCount
    self.pointerHoverHandlerCount = pointerHoverHandlerCount
    self.gestureRecognizerCount = gestureRecognizerCount
    self.gestureStateBindingCount = gestureStateBindingCount
  }
}

@MainActor
package struct RuntimeRegistrationSet {
  package let actionRegistry: LocalActionRegistry?
  package let keyHandlerRegistry: LocalKeyHandlerRegistry?
  package let terminationRegistry: LocalTerminationRegistry?
  package let pointerHandlerRegistry: LocalPointerHandlerRegistry?
  package let gestureRegistry: LocalGestureRegistry?
  package let gestureStateRegistry: LocalGestureStateRegistry?
  package let focusBindingRegistry: LocalFocusBindingRegistry?
  package let focusedValuesRegistry: LocalFocusedValuesRegistry?
  package let scrollPositionRegistry: LocalScrollPositionRegistry?
  package let lifecycleRegistry: LocalLifecycleRegistry?
  package let taskRegistry: LocalTaskRegistry?
  package let preferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package let commandRegistry: CommandRegistry?
  package let dropDestinationRegistry: DropDestinationRegistry?

  package init(
    actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    terminationRegistry: LocalTerminationRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    gestureRegistry: LocalGestureRegistry? = nil,
    gestureStateRegistry: LocalGestureStateRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    scrollPositionRegistry: LocalScrollPositionRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil,
    commandRegistry: CommandRegistry? = nil,
    dropDestinationRegistry: DropDestinationRegistry? = nil
  ) {
    self.actionRegistry = actionRegistry
    self.keyHandlerRegistry = keyHandlerRegistry
    self.terminationRegistry = terminationRegistry
    self.pointerHandlerRegistry = pointerHandlerRegistry
    self.gestureRegistry = gestureRegistry
    self.gestureStateRegistry = gestureStateRegistry
    self.focusBindingRegistry = focusBindingRegistry
    self.focusedValuesRegistry = focusedValuesRegistry
    self.scrollPositionRegistry = scrollPositionRegistry
    self.lifecycleRegistry = lifecycleRegistry
    self.taskRegistry = taskRegistry
    self.preferenceObservationRegistry = preferenceObservationRegistry
    self.commandRegistry = commandRegistry
    self.dropDestinationRegistry = dropDestinationRegistry
  }

  @MainActor
  package static func scratch() -> RuntimeRegistrationSet {
    RuntimeRegistrationSet(
      actionRegistry: LocalActionRegistry(),
      keyHandlerRegistry: LocalKeyHandlerRegistry(),
      terminationRegistry: LocalTerminationRegistry(),
      pointerHandlerRegistry: LocalPointerHandlerRegistry(),
      gestureRegistry: LocalGestureRegistry(),
      gestureStateRegistry: LocalGestureStateRegistry(),
      focusBindingRegistry: LocalFocusBindingRegistry(),
      focusedValuesRegistry: LocalFocusedValuesRegistry(),
      scrollPositionRegistry: LocalScrollPositionRegistry(),
      lifecycleRegistry: LocalLifecycleRegistry(),
      taskRegistry: LocalTaskRegistry(),
      preferenceObservationRegistry: LocalPreferenceObservationRegistry(),
      commandRegistry: CommandRegistry(),
      dropDestinationRegistry: DropDestinationRegistry()
    )
  }

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
