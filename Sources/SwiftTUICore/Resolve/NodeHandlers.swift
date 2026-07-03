@MainActor
package struct NodeHandlers {
  package var actionRegistrations: [Identity: LocalActionRegistry.Registration]
  package var actionRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler]
  package var keyHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var keyPressHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.KeyPressHandler]]
  package var keyPressHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var keyPressHandlerRegistrationOrdinals: [Identity: UInt64]
  package var pasteHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.PasteHandler]]
  package var pasteHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var pasteHandlerRegistrationOrdinals: [Identity: UInt64]
  package var terminationHandlerRegistrations: [Identity: [LocalTerminationRegistry.Handler]]
  package var terminationHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler]
  package var pointerHandlerRegistrationOwners: [RouteID: RuntimeRegistrationOwnerKey]
  package var pointerHoverHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.HoverHandler]
  package var pointerHoverHandlerRegistrationOwners: [RouteID: RuntimeRegistrationOwnerKey]
  package var gestureRegistrations: [Identity: AnyGestureRecognizer]
  package var gestureRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var gestureStateRegistrations: [Identity: [AnyGestureStateBinding]]
  package var gestureStateRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var defaultFocusRegistrations: DefaultFocusRegistrationSnapshot
  package var focusBindingRegistrations: [FocusBindingRegistrationSnapshot]
  package var focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot]
  package var scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot]
  package var lifecycleRegistrations: LifecycleHandlerSnapshot
  package var taskRegistrations: [Identity: [TaskRegistration]]
  package var taskRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey]
  package var preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot]
  package var commandRegistrations: CommandRegistrySnapshot
  package var dropDestinationRegistrations: DropDestinationRegistrySnapshot

  package init(
    actionRegistrations: [Identity: LocalActionRegistry.Registration] = [:],
    actionRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    keyHandlerRegistrations: [Identity: LocalKeyHandlerRegistry.Handler] = [:],
    keyHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    keyPressHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.KeyPressHandler]] = [:],
    keyPressHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    keyPressHandlerRegistrationOrdinals: [Identity: UInt64] = [:],
    pasteHandlerRegistrations: [Identity: [LocalKeyHandlerRegistry.PasteHandler]] = [:],
    pasteHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    pasteHandlerRegistrationOrdinals: [Identity: UInt64] = [:],
    terminationHandlerRegistrations: [Identity: [LocalTerminationRegistry.Handler]] = [:],
    terminationHandlerRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    pointerHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.Handler] = [:],
    pointerHandlerRegistrationOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    pointerHoverHandlerRegistrations: [RouteID: LocalPointerHandlerRegistry.HoverHandler] = [:],
    pointerHoverHandlerRegistrationOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    gestureRegistrations: [Identity: AnyGestureRecognizer] = [:],
    gestureRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    gestureStateRegistrations: [Identity: [AnyGestureStateBinding]] = [:],
    gestureStateRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    defaultFocusRegistrations: DefaultFocusRegistrationSnapshot = .init(),
    focusBindingRegistrations: [FocusBindingRegistrationSnapshot] = [],
    focusedValuesRegistrations: [FocusedValuesRegistrationSnapshot] = [],
    scrollPositionRegistrations: [ScrollPositionRegistrationSnapshot] = [],
    lifecycleRegistrations: LifecycleHandlerSnapshot = .init(),
    taskRegistrations: [Identity: [TaskRegistration]] = [:],
    taskRegistrationOwners: [Identity: RuntimeRegistrationOwnerKey] = [:],
    preferenceObservationRegistrations: [PreferenceObservationRegistrationSnapshot] = [],
    commandRegistrations: CommandRegistrySnapshot = .init(),
    dropDestinationRegistrations: DropDestinationRegistrySnapshot = .init()
  ) {
    self.actionRegistrations = actionRegistrations
    self.actionRegistrationOwners = actionRegistrationOwners
    self.keyHandlerRegistrations = keyHandlerRegistrations
    self.keyHandlerRegistrationOwners = keyHandlerRegistrationOwners
    self.keyPressHandlerRegistrations = keyPressHandlerRegistrations
    self.keyPressHandlerRegistrationOwners = keyPressHandlerRegistrationOwners
    self.keyPressHandlerRegistrationOrdinals = keyPressHandlerRegistrationOrdinals
    self.pasteHandlerRegistrations = pasteHandlerRegistrations
    self.pasteHandlerRegistrationOwners = pasteHandlerRegistrationOwners
    self.pasteHandlerRegistrationOrdinals = pasteHandlerRegistrationOrdinals
    self.terminationHandlerRegistrations = terminationHandlerRegistrations
    self.terminationHandlerRegistrationOwners = terminationHandlerRegistrationOwners
    self.pointerHandlerRegistrations = pointerHandlerRegistrations
    self.pointerHandlerRegistrationOwners = pointerHandlerRegistrationOwners
    self.pointerHoverHandlerRegistrations = pointerHoverHandlerRegistrations
    self.pointerHoverHandlerRegistrationOwners = pointerHoverHandlerRegistrationOwners
    self.gestureRegistrations = gestureRegistrations
    self.gestureRegistrationOwners = gestureRegistrationOwners
    self.gestureStateRegistrations = gestureStateRegistrations
    self.gestureStateRegistrationOwners = gestureStateRegistrationOwners
    self.defaultFocusRegistrations = defaultFocusRegistrations
    self.focusBindingRegistrations = focusBindingRegistrations
    self.focusedValuesRegistrations = focusedValuesRegistrations
    self.scrollPositionRegistrations = scrollPositionRegistrations
    self.lifecycleRegistrations = lifecycleRegistrations
    self.taskRegistrations = taskRegistrations
    self.taskRegistrationOwners = taskRegistrationOwners
    self.preferenceObservationRegistrations = preferenceObservationRegistrations
    self.commandRegistrations = commandRegistrations
    self.dropDestinationRegistrations = dropDestinationRegistrations
  }

  package mutating func reset() {
    self = .init()
  }

  package var hasRuntimeRegistrations: Bool {
    !actionRegistrations.isEmpty
      || !keyHandlerRegistrations.isEmpty
      || !keyPressHandlerRegistrations.isEmpty
      || !pasteHandlerRegistrations.isEmpty
      || !terminationHandlerRegistrations.isEmpty
      || !pointerHandlerRegistrations.isEmpty
      || !pointerHoverHandlerRegistrations.isEmpty
      || !gestureRegistrations.isEmpty
      || !gestureStateRegistrations.isEmpty
      || defaultFocusRegistrations != DefaultFocusRegistrationSnapshot()
      || !focusBindingRegistrations.isEmpty
      || !focusedValuesRegistrations.isEmpty
      || !scrollPositionRegistrations.isEmpty
      || !lifecycleRegistrations.isEmpty
      || !taskRegistrations.isEmpty
      || !preferenceObservationRegistrations.isEmpty
      || !commandRegistrations.isEmpty
      || !dropDestinationRegistrations.isEmpty
  }

  package mutating func recordAction(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?
  ) {
    recordAction(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity,
      owner: .current(identity: identity)
    )
  }

  package mutating func recordAction(
    identity: Identity,
    handler: @escaping LocalActionRegistry.Handler,
    followUpInvalidationIdentity: Identity?,
    owner: RuntimeRegistrationOwnerKey
  ) {
    actionRegistrationOwners[identity] = owner
    actionRegistrations[identity] = .init(
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  package mutating func recordKeyHandler(
    identity: Identity,
    handler: @escaping LocalKeyHandlerRegistry.Handler
  ) {
    keyHandlerRegistrationOwners[identity] = .current(identity: identity)
    keyHandlerRegistrations[identity] = handler
  }

  package mutating func recordKeyPressHandler(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.KeyPressHandler
  ) {
    keyPressHandlerRegistrationOwners[identity] = .current(identity: identity)
    keyPressHandlerRegistrationOrdinals[identity] = ordinal
    keyPressHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordPasteHandler(
    identity: Identity,
    ordinal: UInt64,
    handler: @escaping LocalKeyHandlerRegistry.PasteHandler
  ) {
    pasteHandlerRegistrationOwners[identity] = .current(identity: identity)
    pasteHandlerRegistrationOrdinals[identity] = ordinal
    pasteHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordTerminationHandler(
    identity: Identity,
    handler: @escaping LocalTerminationRegistry.Handler
  ) {
    terminationHandlerRegistrationOwners[identity] = .current(identity: identity)
    terminationHandlerRegistrations[identity, default: []].append(handler)
  }

  package mutating func recordPointerHandler(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.Handler
  ) {
    pointerHandlerRegistrationOwners[routeID] = .current(identity: routeID.identity)
    pointerHandlerRegistrations[routeID] = handler
  }

  package mutating func recordPointerHoverHandler(
    routeID: RouteID,
    handler: @escaping LocalPointerHandlerRegistry.HoverHandler
  ) {
    pointerHoverHandlerRegistrationOwners[routeID] = .current(identity: routeID.identity)
    pointerHoverHandlerRegistrations[routeID] = handler
  }

  package mutating func recordGesture(
    identity: Identity,
    recognizer: AnyGestureRecognizer
  ) {
    gestureRegistrationOwners[identity] = .current(identity: identity)
    gestureRegistrations[identity] = recognizer
  }

  package mutating func recordGestureStateBinding(
    identity: Identity,
    binding: AnyGestureStateBinding
  ) {
    gestureStateRegistrationOwners[identity] = .current(identity: identity)
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
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycleRegistrations.recordAppear(registration)
  }

  package mutating func recordLifecycleDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycleRegistrations.recordDisappear(registration)
  }

  package mutating func recordLifecycleChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    lifecycleRegistrations.recordChange(registration)
  }

  package mutating func recordTask(
    identity: Identity,
    registration: TaskRegistration
  ) {
    taskRegistrationOwners[identity] = .current(identity: identity)
    var identityRegistrations = taskRegistrations[identity] ?? []
    if let index = identityRegistrations.firstIndex(where: {
      $0.descriptor.id == registration.descriptor.id
    }) {
      identityRegistrations[index] = registration
    } else {
      identityRegistrations.append(registration)
    }
    taskRegistrations[identity] = identityRegistrations
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
      commandRegistrations.ownersByScope[identity] =
        registration.ownersByScope[identity] ?? .current(identity: identity)
    }
  }

  package mutating func recordDropDestination(
    _ registration: DropDestinationRegistrySnapshot
  ) {
    for (identity, handler) in registration.handlersByScope {
      dropDestinationRegistrations.handlersByScope[identity] = handler
      dropDestinationRegistrations.ownersByScope[identity] =
        registration.ownersByScope[identity] ?? .current(identity: identity)
    }
  }
}
