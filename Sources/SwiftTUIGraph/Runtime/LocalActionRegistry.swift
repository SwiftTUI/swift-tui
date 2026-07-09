@MainActor
package final class LocalActionRegistry: Equatable {
  package typealias Handler = @MainActor () -> Bool
  package struct Registration {
    package var handler: Handler
    package var followUpInvalidationIdentity: Identity?

    package init(
      handler: @escaping Handler,
      followUpInvalidationIdentity: Identity? = nil
    ) {
      self.handler = handler
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
    followUpInvalidationIdentity: Identity? = nil
  ) {
    let registration = Registration(
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
    store.set(registration, for: identity, owner: .current(identity: identity))
    ViewNodeContext.current?.recordActionRegistration(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  @discardableResult
  package func dispatch(identity: Identity) -> Bool {
    store[identity]?.handler() ?? false
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
