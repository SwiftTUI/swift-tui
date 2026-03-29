@MainActor
package final class LocalActionRegistry: Equatable {
  package typealias Handler = @MainActor () -> Bool

  private var handlers: [Identity: Handler] = [:]

  package init() {}

  nonisolated package static func == (lhs: LocalActionRegistry, rhs: LocalActionRegistry) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    handlers[identity] = handler
  }

  @discardableResult
  package func dispatch(identity: Identity) -> Bool {
    handlers[identity]?() ?? false
  }

  package func hasHandler(
    identity: Identity
  ) -> Bool {
    handlers[identity] != nil
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
  }

  package func snapshot() -> [Identity: Handler] {
    handlers
  }

  package func restore(_ snapshot: [Identity: Handler]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handler) in snapshot {
      handlers[identity] = handler
    }
  }
}
