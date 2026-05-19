extension NodeHandlers {
  func debugTotalStateSnapshot() -> ViewNode.DebugTotalStateSnapshot.HandlerSnapshot {
    ViewNode.DebugTotalStateSnapshot.HandlerSnapshot(
      actionRegistrationIdentities: sortedIdentityStrings(actionRegistrations.keys),
      keyHandlerRegistrationIdentities: sortedIdentityStrings(keyHandlerRegistrations.keys),
      keyPressHandlerRegistrationIdentities: sortedIdentityStrings(
        keyPressHandlerRegistrations.keys
      ),
      pasteHandlerRegistrationIdentities: sortedIdentityStrings(pasteHandlerRegistrations.keys),
      terminationHandlerRegistrationIdentities: sortedIdentityStrings(
        terminationHandlerRegistrations.keys
      ),
      pointerHandlerRouteIDs: sortedDescriptions(pointerHandlerRegistrations.keys),
      pointerHoverHandlerRouteIDs: sortedDescriptions(pointerHoverHandlerRegistrations.keys),
      gestureRegistrationIdentities: sortedIdentityStrings(gestureRegistrations.keys),
      gestureStateRegistrationIdentities: sortedIdentityStrings(gestureStateRegistrations.keys),
      defaultFocusScopeIdentities: sortedIdentityStrings(
        defaultFocusRegistrations.scopes.map(\.identity)
      ),
      defaultFocusCandidateIdentities: sortedIdentityStrings(
        defaultFocusRegistrations.candidates.map(\.identity)
      ),
      focusBindingIdentities: sortedIdentityStrings(focusBindingRegistrations.map(\.identity)),
      focusedValuesIdentities: sortedIdentityStrings(focusedValuesRegistrations.map(\.identity)),
      scrollPositionIdentities: sortedIdentityStrings(scrollPositionRegistrations.map(\.identity)),
      lifecycleHandlerIDs: (Array(lifecycleRegistrations.appearHandlers.keys)
        + Array(lifecycleRegistrations.disappearHandlers.keys)
        + Array(lifecycleRegistrations.changeHandlers.keys)).sorted(),
      taskRegistrationIdentities: sortedIdentityStrings(taskRegistrations.keys),
      preferenceObservationHandlerIDs:
        preferenceObservationRegistrations
        .map(\.handlerID)
        .sorted(),
      commandRegistrations: commandRegistrations.keyCommandsByScope
        .flatMap { identity, commands in
          commands.map { binding, command in
            "\(identity.description):\(binding):\(command.description):\(command.isEnabled)"
          }
        }
        .sorted(),
      dropDestinationIdentities: sortedIdentityStrings(
        dropDestinationRegistrations.handlersByScope.keys)
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
