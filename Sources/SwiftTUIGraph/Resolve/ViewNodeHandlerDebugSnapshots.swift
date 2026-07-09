extension NodeHandlers {
  func debugTotalStateSnapshot() -> ViewNode.DebugTotalStateSnapshot.HandlerSnapshot {
    ViewNode.DebugTotalStateSnapshot.HandlerSnapshot(
      actionRegistrationIdentities: sortedIdentityStrings(action.registrations.keys),
      keyHandlerRegistrationIdentities: sortedIdentityStrings(keyHandler.handlers.keys),
      keyPressHandlerRegistrationIdentities: sortedIdentityStrings(
        keyHandler.keyPress.handlers.keys
      ),
      pasteHandlerRegistrationIdentities: sortedIdentityStrings(keyHandler.paste.handlers.keys),
      terminationHandlerRegistrationIdentities: sortedIdentityStrings(
        termination.handlers.keys
      ),
      pointerHandlerRouteIDs: sortedDescriptions(pointer.handlers.keys),
      pointerHoverHandlerRouteIDs: sortedDescriptions(pointer.hoverHandlers.keys),
      gestureRegistrationIdentities: sortedIdentityStrings(gesture.recognizers.keys),
      gestureStateRegistrationIdentities: sortedIdentityStrings(gestureState.bindings.keys),
      defaultFocusScopeIdentities: sortedIdentityStrings(
        defaultFocus.scopes.map(\.identity)
      ),
      defaultFocusCandidateIdentities: sortedIdentityStrings(
        defaultFocus.candidates.map(\.identity)
      ),
      focusBindingIdentities: sortedIdentityStrings(focusBinding.registrations.map(\.identity)),
      focusedValuesIdentities: sortedIdentityStrings(focusedValues.registrations.map(\.identity)),
      scrollPositionIdentities: sortedIdentityStrings(
        scrollPosition.registrations.map(\.identity)
      ),
      lifecycleHandlerIDs: (Array(lifecycle.appearHandlers.keys)
        + Array(lifecycle.disappearHandlers.keys)
        + Array(lifecycle.changeHandlers.keys)).sorted(),
      taskRegistrationIdentities: sortedIdentityStrings(task.registrations.keys),
      preferenceObservationHandlerIDs:
        preferenceObservation.registrations
        .map(\.handlerID)
        .sorted(),
      commandRegistrations: command.keyCommandsByScope
        .flatMap { identity, commands in
          commands.map { binding, command in
            "\(identity.description):\(binding):\(command.description):\(command.isEnabled)"
          }
        }
        .sorted(),
      dropDestinationIdentities: sortedIdentityStrings(
        dropDestination.handlersByScope.keys)
    )
  }
}

private func sortedIdentityStrings<Identities: Sequence>(
  _ identities: Identities
) -> [String] where Identities.Element == Identity {
  identities.map(\.description).sorted()
}

private func sortedDescriptions<Values: Sequence>(
  _ values: Values
) -> [String] {
  values.map { String(describing: $0) }.sorted()
}
