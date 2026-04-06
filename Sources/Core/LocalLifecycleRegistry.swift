package struct LifecycleHandlerSnapshot: Sendable {
  package var appearHandlers: [String: LocalLifecycleRegistry.Handler]
  package var disappearHandlers: [String: LocalLifecycleRegistry.Handler]

  package init(
    appearHandlers: [String: LocalLifecycleRegistry.Handler] = [:],
    disappearHandlers: [String: LocalLifecycleRegistry.Handler] = [:]
  ) {
    self.appearHandlers = appearHandlers
    self.disappearHandlers = disappearHandlers
  }
}

@MainActor
package final class LocalLifecycleRegistry: Equatable {
  package typealias Handler = @MainActor @Sendable () -> Void

  private var appearHandlers: [String: Handler] = [:]
  private var disappearHandlers: [String: Handler] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalLifecycleRegistry,
    rhs: LocalLifecycleRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func registerAppear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    appearHandlers[handlerID] = handler
    ViewNodeContext.current?.recordLifecycleAppearRegistration(
      handlerID: handlerID,
      handler: handler
    )
  }

  package func registerDisappear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    disappearHandlers[handlerID] = handler
    ViewNodeContext.current?.recordLifecycleDisappearRegistration(
      handlerID: handlerID,
      handler: handler
    )
  }

  package func appearHandler(
    for handlerID: String
  ) -> Handler? {
    appearHandlers[handlerID]
  }

  package func disappearHandler(
    for handlerID: String
  ) -> Handler? {
    disappearHandlers[handlerID]
  }

  package func reset() {
    appearHandlers.removeAll(keepingCapacity: true)
    disappearHandlers.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for handlerID in appearHandlers.keys
    where identityMatchesAnySubtreeRoot(
      lifecycleHandlerIdentity(from: handlerID),
      roots: roots
    ) {
      appearHandlers.removeValue(forKey: handlerID)
    }
    for handlerID in disappearHandlers.keys
    where identityMatchesAnySubtreeRoot(
      lifecycleHandlerIdentity(from: handlerID),
      roots: roots
    ) {
      disappearHandlers.removeValue(forKey: handlerID)
    }
  }

  package func snapshot() -> LifecycleHandlerSnapshot {
    .init(
      appearHandlers: appearHandlers,
      disappearHandlers: disappearHandlers
    )
  }

  package func restore(
    _ snapshot: LifecycleHandlerSnapshot
  ) {
    guard !snapshot.appearHandlers.isEmpty || !snapshot.disappearHandlers.isEmpty else {
      return
    }

    for (handlerID, handler) in snapshot.appearHandlers {
      appearHandlers[handlerID] = handler
    }
    for (handlerID, handler) in snapshot.disappearHandlers {
      disappearHandlers[handlerID] = handler
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

private func lifecycleHandlerIdentity(
  from handlerID: String
) -> Identity {
  let identityPath = String(handlerID.split(separator: "#", maxSplits: 1).first ?? "")
  guard !identityPath.isEmpty else {
    return .init(components: [] as [IdentityComponent])
  }
  return .init(
    components: identityPath.split(separator: "/").map(String.init)
  )
}
