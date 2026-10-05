@MainActor
package final class LocalActionRegistry: Equatable {
  package typealias Handler = @MainActor () -> Bool
  package typealias AccessibilityHandler =
    @MainActor (AccessibilityAction) -> AccessibilityActionOutcome
  package struct Registration {
    package var handler: Handler
    package var accessibilityHandler: AccessibilityHandler?
    /// Semantic-only operations must not intercept keyboard/pointer activation.
    package var hasActivationHandler: Bool
    package var followUpInvalidationIdentity: Identity?

    package init(
      handler: @escaping Handler,
      accessibilityHandler: AccessibilityHandler? = nil,
      hasActivationHandler: Bool = true,
      followUpInvalidationIdentity: Identity? = nil
    ) {
      self.handler = handler
      self.accessibilityHandler = accessibilityHandler
      self.hasActivationHandler = hasActivationHandler
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

  package func hasActivationHandler(identity: Identity) -> Bool {
    store[identity]?.hasActivationHandler == true
  }

  /// Intentionally decorates a control's one registration. Unlike registering
  /// another primitive at the same identity, this preserves its default action
  /// and delegates unhandled assistive operations to the preceding contribution.
  package func composeAccessibility(
    identity: Identity, preservingExisting: Bool, followUpInvalidationIdentity: Identity?,
    contribution: @escaping @MainActor (AccessibilityAction) -> AccessibilityActionOutcome?
  ) {
    // The first authored operation starts a fresh chain on every resolve.
    // Keeping the previous frame here would retain obsolete callbacks forever.
    let preservesCurrent =
      ViewNodeContext.current?.hasCurrentActionRegistration(identity: identity) == true
    let inherited = preservingExisting || preservesCurrent ? store[identity] : nil
    let handler: Handler = { inherited?.handler() ?? false }
    let accessibility: AccessibilityHandler = { action in
      if let result = contribution(action) { return result }
      if let previous = inherited?.accessibilityHandler { return previous(action) }
      guard action == .activate, let inherited else { return .unsupported }
      return inherited.handler() ? .changed : .unchanged
    }
    let registration = Registration(
      handler: handler, accessibilityHandler: accessibility,
      hasActivationHandler: inherited?.hasActivationHandler ?? false,
      followUpInvalidationIdentity: followUpInvalidationIdentity)
    store.set(registration, for: identity, owner: .current(identity: identity))
    ViewNodeContext.current?.recordComposedActionRegistration(
      identity: identity, registration: registration)
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
