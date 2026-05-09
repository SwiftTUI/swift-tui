package struct NodeHandlers {
  package var actionRegistrations: [Identity: LocalActionRegistry.Registration]
  package var keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler]
  package var keyPressHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.KeyPressHandler]]
  package var pasteHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.PasteHandler]]
  package var terminationHandlerRegistrations: [Identity: [LocalTerminationRegistry.Handler]]
  package var pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler]
  package var pointerHoverHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.HoverHandler]
  package var gestureRegistrations: [Identity: AnyGestureRecognizer]
  package var gestureStateRegistrations: [Identity: [AnyGestureStateBinding]]
  package var defaultFocusRegistrations: DefaultFocusRegistrationSnapshot
  package var focusBindingRegistrations: [FocusBindingRegistrationSnapshot]
  package var focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot]
  package var scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot]
  package var lifecycleRegistrations: LifecycleHandlerSnapshot
  package var taskRegistrations: [Identity: TaskRegistration]
  package var preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot]
  package var commandRegistrations: CommandRegistrySnapshot
  package var dropDestinationRegistrations: DropDestinationRegistrySnapshot

  package init(
    actionRegistrations: [Identity: LocalActionRegistry.Registration] = [:],
    keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler] = [:],
    keyPressHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.KeyPressHandler]] = [:],
    pasteHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.PasteHandler]] = [:],
    terminationHandlerRegistrations: [Identity: [LocalTerminationRegistry.Handler]] = [:],
    pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler] = [:],
    pointerHoverHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.HoverHandler] = [:],
    gestureRegistrations: [Identity: AnyGestureRecognizer] = [:],
    gestureStateRegistrations: [Identity: [AnyGestureStateBinding]] = [:],
    defaultFocusRegistrations: DefaultFocusRegistrationSnapshot = .init(),
    focusBindingRegistrations: [FocusBindingRegistrationSnapshot] = [],
    focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot] = [],
    scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot] = [],
    lifecycleRegistrations: LifecycleHandlerSnapshot = .init(),
    taskRegistrations: [Identity: TaskRegistration] = [:],
    preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot] = [],
    commandRegistrations: CommandRegistrySnapshot = .init(),
    dropDestinationRegistrations: DropDestinationRegistrySnapshot = .init()
  ) {
    self.actionRegistrations = actionRegistrations
    self.keyHandlerRegistrations = keyHandlerRegistrations
    self.keyPressHandlerRegistrations = keyPressHandlerRegistrations
    self.pasteHandlerRegistrations = pasteHandlerRegistrations
    self.terminationHandlerRegistrations = terminationHandlerRegistrations
    self.pointerHandlerRegistrations = pointerHandlerRegistrations
    self.pointerHoverHandlerRegistrations = pointerHoverHandlerRegistrations
    self.gestureRegistrations = gestureRegistrations
    self.gestureStateRegistrations = gestureStateRegistrations
    self.defaultFocusRegistrations = defaultFocusRegistrations
    self.focusBindingRegistrations = focusBindingRegistrations
    self.focusedValuesRegistrations = focusedValuesRegistrations
    self.scrollPositionRegistrations = scrollPositionRegistrations
    self.lifecycleRegistrations = lifecycleRegistrations
    self.taskRegistrations = taskRegistrations
    self.preferenceObservationRegistrations = preferenceObservationRegistrations
    self.commandRegistrations = commandRegistrations
    self.dropDestinationRegistrations = dropDestinationRegistrations
  }

  package mutating func reset() {
    self = .init()
  }

  package mutating func recordAction(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    actionRegistrations[identity] = .init(
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  package mutating func recordKeyHandler(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.Handler
  ) {
    keyHandlerRegistrations[identity] = handler
  }

  package mutating func recordKeyPressHandler(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    keyPressHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordPasteHandler(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    pasteHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordTerminationHandler(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    terminationHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordPointerHandler(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    pointerHandlerRegistrations[routeID] = handler
  }

  package mutating func recordPointerHoverHandler(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    pointerHoverHandlerRegistrations[routeID] = handler
  }

  package mutating func recordGesture(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    gestureRegistrations[identity] = recognizer
  }

  package mutating func recordGestureStateBinding(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    gestureStateRegistrations[identity, default: []].append(binding)
  }

  package mutating func recordDefaultFocus(
    _ registration: DefaultFocusScopeRegistrationSnapshot
  ) {
    if !defaultFocusRegistrations.scopes.contains(where: {
      $0.namespace == registration.namespace && $0.identity == registration.identity
    }) {
      defaultFocusRegistrations.scopes.append(registration)
    }
  }

  package mutating func recordDefaultFocus(
    _ registration: DefaultFocusCandidateRegistrationSnapshot
  ) {
    if !defaultFocusRegistrations.candidates.contains(where: {
      $0.namespace == registration.namespace && $0.identity == registration.identity
    }) {
      defaultFocusRegistrations.candidates.append(registration)
    }
  }

  package mutating func recordFocusBinding(
    _ registration: FocusBindingRegistrationSnapshot
  ) {
    focusBindingRegistrations.append(registration)
  }

  package mutating func recordFocusedValues(
    _ registration: FocusedValuesRegistrationSnapshot
  ) {
    if let existingIndex = focusedValuesRegistrations.firstIndex(where: {
      $0.identity == registration.identity
    }) {
      focusedValuesRegistrations[existingIndex].descendantIdentities.formUnion(
        registration.descendantIdentities
      )
      focusedValuesRegistrations[existingIndex].values.merge(registration.values)
    } else {
      focusedValuesRegistrations.append(registration)
    }
  }

  package mutating func recordScrollPosition(
    _ registration: ScrollPositionRegistrationSnapshot
  ) {
    if let existingIndex = scrollPositionRegistrations.firstIndex(where: {
      $0.identity == registration.identity
    }) {
      scrollPositionRegistrations[existingIndex] = registration
    } else {
      scrollPositionRegistrations.append(registration)
    }
  }

  package mutating func recordLifecycleAppear(
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    lifecycleRegistrations.appearHandlers[handlerID] = handler
  }

  package mutating func recordLifecycleDisappear(
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    lifecycleRegistrations.disappearHandlers[handlerID] = handler
  }

  package mutating func recordLifecycleChange(
    handlerID: String,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    lifecycleRegistrations.changeHandlers[handlerID] = handler
  }

  package mutating func recordTask(
    identity: Identity,
    registration: TaskRegistration
  ) {
    taskRegistrations[identity] = registration
  }

  package mutating func recordPreferenceObservation(
    _ registration: PreferenceObservationRegistrationSnapshot
  ) {
    preferenceObservationRegistrations.append(registration)
  }

  package mutating func recordCommand(
    _ registration: CommandRegistrySnapshot
  ) {
    for (identity, commands) in registration.keyCommandsByScope {
      commandRegistrations.keyCommandsByScope[identity] = commands
    }
    for (identity, commands) in registration.paletteCommandsByScope {
      commandRegistrations.paletteCommandsByScope[identity] = commands
    }
  }

  package mutating func recordDropDestination(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    for (identity, handler) in registration.handlersByScope {
      dropDestinationRegistrations.handlersByScope[identity] = handler
    }
  }
}
