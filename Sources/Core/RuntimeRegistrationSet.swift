@MainActor
package struct RuntimeRegistrationSet {
  package let actionRegistry: LocalActionRegistry?
  package let keyHandlerRegistry: LocalKeyHandlerRegistry?
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

  package func resetAll() {
    actionRegistry?.reset()
    keyHandlerRegistry?.reset()
    pointerHandlerRegistry?.reset()
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
    pointerHandlerRegistry?.removeSubtrees(rootedAt: roots)
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
    actionRegistry?.restore(handlers.actionRegistrations)
    keyHandlerRegistry?.restore(handlers.keyHandlerRegistrations)
    keyHandlerRegistry?.restoreKeyPressHandlers(
      handlers.keyPressHandlerRegistrations
    )
    pointerHandlerRegistry?.restore(handlers.pointerHandlerRegistrations)
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
    commandRegistry?.restoreKeyCommands(handlers.keyCommandRegistrations)
    commandRegistry?.restorePaletteCommands(handlers.paletteCommandRegistrations)
    dropDestinationRegistry?.restore(handlers.dropDestinationRegistrations)
  }
}
