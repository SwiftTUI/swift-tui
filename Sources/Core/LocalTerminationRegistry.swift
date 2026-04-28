/// A request to end an interactive terminal session.
public enum TerminationRequest: Equatable, Sendable {
  /// A configured exit key was pressed.
  case userExit(KeyPress)
  /// A host signal requested termination.
  case signal(String)
  /// The terminal input stream ended.
  ///
  /// Handlers are notified for this request, but cancellation cannot keep a
  /// session alive after its input stream has ended.
  case inputEnded
}

/// The result of a termination request handler.
public enum TerminationDisposition: Equatable, Sendable {
  /// Allow the session to terminate.
  case allow
  /// Cancel the termination request when cancellation is possible.
  case cancel
}

@MainActor
package final class LocalTerminationRegistry: Equatable {
  package typealias Handler = @MainActor (TerminationRequest) -> TerminationDisposition

  private var handlers: [Identity: [Handler]] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalTerminationRegistry,
    rhs: LocalTerminationRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    handler: @escaping Handler
  ) {
    handlers[identity, default: []].append(handler)
    ViewNodeContext.current?.recordTerminationHandlerRegistration(
      identity: identity,
      handler: handler
    )
  }

  package func dispatch(
    _ request: TerminationRequest,
    preferredPath: [Identity]
  ) -> TerminationDisposition {
    var visited = Set<Identity>()
    var orderedIdentities: [Identity] = []

    for identity in preferredPath.reversed() where visited.insert(identity).inserted {
      orderedIdentities.append(identity)
    }

    let remaining = handlers.keys
      .filter { !visited.contains($0) }
      .sorted { lhs, rhs in
        if lhs.components.count != rhs.components.count {
          return lhs.components.count > rhs.components.count
        }
        return lhs < rhs
      }
    orderedIdentities.append(contentsOf: remaining)

    for identity in orderedIdentities {
      guard let identityHandlers = handlers[identity] else {
        continue
      }
      for handler in identityHandlers.reversed() {
        if handler(request) == .cancel {
          return .cancel
        }
      }
    }

    return .allow
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for identity in handlers.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
    }) {
      handlers.removeValue(forKey: identity)
    }
  }

  package func snapshot() -> [Identity: [Handler]] {
    handlers
  }

  package func restore(_ snapshot: [Identity: [Handler]]) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, handlers) in snapshot {
      self.handlers[identity] = handlers
    }
  }
}

private func identityMatchesAnySubtreeRoot(
  _ identity: Identity,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
  }
}
