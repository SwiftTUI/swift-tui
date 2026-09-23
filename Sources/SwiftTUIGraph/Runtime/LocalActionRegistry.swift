@MainActor
package final class LocalActionRegistry: Equatable {
  package typealias Handler = @MainActor () -> Bool
  package typealias AccessibilityHandler =
    @MainActor (AccessibilityAction) -> AccessibilityActionOutcome
  package struct Registration {
    package var handler: Handler
    package var accessibilityHandler: AccessibilityHandler?
    package var followUpInvalidationIdentity: Identity?

    package init(
      handler: @escaping Handler,
      accessibilityHandler: AccessibilityHandler? = nil,
      followUpInvalidationIdentity: Identity? = nil
    ) {
      self.handler = handler
      self.accessibilityHandler = accessibilityHandler
      self.followUpInvalidationIdentity = followUpInvalidationIdentity
    }
  }

  private var store = IdentityKeyedRegistryStorage<Registration>()

  package init() {}

  nonisolated package static func == (lhs: LocalActionRegistry, rhs: LocalActionRegistry) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler,
    accessibilityHandler: AccessibilityHandler? = nil,
    followUpInvalidationIdentity: Identity? = nil
  ) {
    let registration = Registration(
      handler: handler,
      accessibilityHandler: accessibilityHandler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
    store.set(registration, for: identity, owner: .current(identity: identity))
    ViewNodeContext.current?.recordActionRegistration(
      identity: identity,
      handler: handler,
      accessibilityHandler: accessibilityHandler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  @discardableResult
  package func dispatch(identity: Identity) -> Bool {
    guard let registration = store[identity] else {
      SoundnessProbeConfiguration.recordActionDispatchMiss(
        "action dispatch: no published handler for \(identity.path)"
      )
      return false
    }
    return registration.handler()
  }

  package func dispatchAccessibility(identity: Identity, action: AccessibilityAction)
    -> AccessibilityActionOutcome
  {
    guard let registration = store[identity] else { return .unsupported }
    if let handler = registration.accessibilityHandler { return handler(action) }
    guard action == .activate else { return .unsupported }
    return registration.handler() ? .changed : .unchanged
  }

  package func followUpInvalidationIdentity(
    for identity: Identity
  ) -> Identity? {
    store[identity]?.followUpInvalidationIdentity
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    store[identity] != nil
  }

  package func reset() {
    store.reset()
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    store.removeSubtrees(rootedAt: roots)
  }

  /// The node axis of teardown — see
  /// ``RuntimeRegistry/removeUnjustifiedRegistrations(_:)``.
  package func removeUnjustifiedRegistrations(
    _ record: (ViewNodeID) -> NodeHandlers?
  ) {
    store.removeUnjustified { identity, owner in
      // An entry restored without an owner carries no node claim to check.
      guard let viewNodeID = owner.viewNodeID else {
        return true
      }
      return record(viewNodeID)?.action.registrations[identity] != nil
    }
  }

  package func snapshot() -> [Identity: Registration] {
    store.values
  }

  package func restore(
    _ snapshot: [Identity: Registration],
    ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    store.restore(snapshot, ownersByIdentity: ownersByIdentity)
  }
}
