@MainActor
package struct RuntimeRegistrationSet {
  package let actionRegistry: LocalActionRegistry?
  package let keyHandlerRegistry: LocalKeyHandlerRegistry?
  package let pointerHandlerRegistry: LocalPointerHandlerRegistry?
  package let focusBindingRegistry: LocalFocusBindingRegistry?
  package let focusedValuesRegistry: LocalFocusedValuesRegistry?
  package let lifecycleRegistry: LocalLifecycleRegistry?
  package let taskRegistry: LocalTaskRegistry?
  package let preferenceObservationRegistry: LocalPreferenceObservationRegistry?
  package let commandRegistry: CommandRegistry?

  package init(
    actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil,
    commandRegistry: CommandRegistry? = nil
  ) {
    self.actionRegistry = actionRegistry
    self.keyHandlerRegistry = keyHandlerRegistry
    self.pointerHandlerRegistry = pointerHandlerRegistry
    self.focusBindingRegistry = focusBindingRegistry
    self.focusedValuesRegistry = focusedValuesRegistry
    self.lifecycleRegistry = lifecycleRegistry
    self.taskRegistry = taskRegistry
    self.preferenceObservationRegistry = preferenceObservationRegistry
    self.commandRegistry = commandRegistry
  }

  package func resetAll() {
    actionRegistry?.reset()
    keyHandlerRegistry?.reset()
    pointerHandlerRegistry?.reset()
    focusBindingRegistry?.reset()
    focusedValuesRegistry?.reset()
    lifecycleRegistry?.reset()
    taskRegistry?.reset()
    preferenceObservationRegistry?.reset()
    commandRegistry?.reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    actionRegistry?.removeSubtrees(rootedAt: roots)
    keyHandlerRegistry?.removeSubtrees(rootedAt: roots)
    pointerHandlerRegistry?.removeSubtrees(rootedAt: roots)
    focusBindingRegistry?.removeSubtrees(rootedAt: roots)
    focusedValuesRegistry?.removeSubtrees(rootedAt: roots)
    lifecycleRegistry?.removeSubtrees(rootedAt: roots)
    taskRegistry?.removeSubtrees(rootedAt: roots)
    preferenceObservationRegistry?.removeSubtrees(rootedAt: roots)
    commandRegistry?.removeSubtrees(rootedAt: roots)
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
    focusBindingRegistry?.restore(handlers.focusBindingRegistrations)
    focusedValuesRegistry?.restore(handlers.focusedValuesRegistrations)
    lifecycleRegistry?.restore(handlers.lifecycleRegistrations)
    taskRegistry?.restore(handlers.taskRegistrations)
    preferenceObservationRegistry?.restore(
      handlers.preferenceObservationRegistrations
    )
  }
}
