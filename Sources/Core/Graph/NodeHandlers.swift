package struct NodeHandlers {
  package var actionRegistrations: [Identity: LocalActionRegistry.Registration]
  package var keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler]
  package var keyPressHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.KeyPressHandler]
  package var pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler]
  package var gestureRegistrations: [Identity: AnyGestureRecognizer]
  package var gestureStateRegistrations: [Identity: [AnyGestureStateBinding]]
  package var focusBindingRegistrations: [FocusBindingRegistrationSnapshot]
  package var focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot]
  package var scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot]
  package var lifecycleRegistrations: LifecycleHandlerSnapshot
  package var taskRegistrations: [Identity: TaskRegistration]
  package var preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot]

  package init(
    actionRegistrations: [Identity: LocalActionRegistry.Registration] = [:],
    keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler] = [:],
    keyPressHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.KeyPressHandler] = [:],
    pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler] = [:],
    gestureRegistrations: [Identity: AnyGestureRecognizer] = [:],
    gestureStateRegistrations: [Identity: [AnyGestureStateBinding]] = [:],
    focusBindingRegistrations: [FocusBindingRegistrationSnapshot] = [],
    focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot] = [],
    scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot] = [],
    lifecycleRegistrations: LifecycleHandlerSnapshot = .init(),
    taskRegistrations: [Identity: TaskRegistration] = [:],
    preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot] = []
  ) {
    self.actionRegistrations = actionRegistrations
    self.keyHandlerRegistrations = keyHandlerRegistrations
    self.keyPressHandlerRegistrations = keyPressHandlerRegistrations
    self.pointerHandlerRegistrations = pointerHandlerRegistrations
    self.gestureRegistrations = gestureRegistrations
    self.gestureStateRegistrations = gestureStateRegistrations
    self.focusBindingRegistrations = focusBindingRegistrations
    self.focusedValuesRegistrations = focusedValuesRegistrations
    self.scrollPositionRegistrations = scrollPositionRegistrations
    self.lifecycleRegistrations = lifecycleRegistrations
    self.taskRegistrations = taskRegistrations
    self.preferenceObservationRegistrations = preferenceObservationRegistrations
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
    keyPressHandlerRegistrations[identity] = handler
  }

  package mutating func recordPointerHandler(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    pointerHandlerRegistrations[routeID] = handler
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
}
