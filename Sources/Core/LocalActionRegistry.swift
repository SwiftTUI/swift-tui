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

  private var handlers: [Identity: Registration] = [:]

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
    handlers[identity] = registration
    ViewNodeContext.current?.recordActionRegistration(
      identity: identity,
      handler: handler,
      followUpInvalidationIdentity: followUpInvalidationIdentity
    )
  }

  @discardableResult
  package func dispatch(identity: Identity) -> Bool {
    handlers[identity]?.handler() ?? false
  }

  package func followUpInvalidationIdentity(
    for identity: Identity
  ) -> Identity? {
    handlers[identity]?.followUpInvalidationIdentity
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    handlers[identity] != nil
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: Registration] {
    handlers
  }

  package func restore(_ snapshot: [Identity: Registration]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, registration) in snapshot {
      handlers[identity] = registration
    }
  }
}
