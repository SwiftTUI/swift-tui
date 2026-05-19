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
  package let defaultFocusRegistry: LocalDefaultFocusRegistry?
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
    defaultFocusRegistry: LocalDefaultFocusRegistry? = nil,
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
    self.defaultFocusRegistry = defaultFocusRegistry
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
      defaultFocusRegistry: LocalDefaultFocusRegistry(),
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
}
