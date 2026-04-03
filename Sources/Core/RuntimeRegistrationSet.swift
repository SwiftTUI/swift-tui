@MainActor
package struct RuntimeRegistrationSet {
  package let actionRegistry: LocalActionRegistry?
  package let keyHandlerRegistry: LocalKeyHandlerRegistry?
  package let pointerHandlerRegistry: LocalPointerHandlerRegistry?
  package let focusBindingRegistry: LocalFocusBindingRegistry?
  package let focusedValuesRegistry: LocalFocusedValuesRegistry?
  package let hotkeyRegistry: HotkeyRegistry?
  package let lifecycleRegistry: LocalLifecycleRegistry?
  package let taskRegistry: LocalTaskRegistry?
  package let preferenceObservationRegistry: LocalPreferenceObservationRegistry?

  package init(
    actionRegistry: LocalActionRegistry? = nil,
    keyHandlerRegistry: LocalKeyHandlerRegistry? = nil,
    pointerHandlerRegistry: LocalPointerHandlerRegistry? = nil,
    focusBindingRegistry: LocalFocusBindingRegistry? = nil,
    focusedValuesRegistry: LocalFocusedValuesRegistry? = nil,
    hotkeyRegistry: HotkeyRegistry? = nil,
    lifecycleRegistry: LocalLifecycleRegistry? = nil,
    taskRegistry: LocalTaskRegistry? = nil,
    preferenceObservationRegistry: LocalPreferenceObservationRegistry? = nil
  ) {
    self.actionRegistry = actionRegistry
    self.keyHandlerRegistry = keyHandlerRegistry
    self.pointerHandlerRegistry = pointerHandlerRegistry
    self.focusBindingRegistry = focusBindingRegistry
    self.focusedValuesRegistry = focusedValuesRegistry
    self.hotkeyRegistry = hotkeyRegistry
    self.lifecycleRegistry = lifecycleRegistry
    self.taskRegistry = taskRegistry
    self.preferenceObservationRegistry = preferenceObservationRegistry
  }

  package func resetAll() {
    actionRegistry?.reset()
    keyHandlerRegistry?.reset()
    pointerHandlerRegistry?.reset()
    focusBindingRegistry?.reset()
    focusedValuesRegistry?.reset()
    hotkeyRegistry?.reset()
    lifecycleRegistry?.reset()
    taskRegistry?.reset()
    preferenceObservationRegistry?.reset()
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
    hotkeyRegistry?.restore(handlers.hotkeyRegistrations)
    lifecycleRegistry?.restore(handlers.lifecycleRegistrations)
    taskRegistry?.restore(handlers.taskRegistrations)
    preferenceObservationRegistry?.restore(
      handlers.preferenceObservationRegistrations
    )
  }
}
