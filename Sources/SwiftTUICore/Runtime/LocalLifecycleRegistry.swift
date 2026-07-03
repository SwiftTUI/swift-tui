package enum LifecycleHandlerKeySuffix: Hashable, Sendable, CustomStringConvertible {
  case appear(ordinal: Int)
  case disappear(ordinal: Int)
  case change(ordinal: Int)
  case legacy(String)

  package var description: String {
    switch self {
    case .appear(let ordinal):
      "appear[\(ordinal)]"
    case .disappear(let ordinal):
      "disappear[\(ordinal)]"
    case .change(let ordinal):
      "change[\(ordinal)]"
    case .legacy(let handlerID):
      handlerID
    }
  }
}

package typealias LifecycleHandlerKey = ViewNodeRuntimeKey<LifecycleHandlerKeySuffix>

package struct LifecycleHandlerRegistration: Sendable {
  package var identity: Identity
  package var key: LifecycleHandlerKey
  package var handlerID: String
  package var handler: LocalLifecycleRegistry.Handler

  package init(
    identity: Identity,
    key: LifecycleHandlerKey,
    handlerID: String? = nil,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    self.identity = identity
    self.key = key
    self.handlerID =
      handlerID
      ?? Self.handlerID(
        identity: identity,
        suffix: key.suffix
      )
    self.handler = handler
  }

  private static func handlerID(
    identity: Identity,
    suffix: LifecycleHandlerKeySuffix
  ) -> String {
    switch suffix {
    case .legacy(let handlerID):
      handlerID
    case .appear, .disappear, .change:
      "\(identity)#\(suffix)"
    }
  }
}

package struct LifecycleHandlerSnapshot: Sendable {
  package var appearHandlers: [String: LocalLifecycleRegistry.Handler]
  package var disappearHandlers: [String: LocalLifecycleRegistry.Handler]
  package var changeHandlers: [String: LocalLifecycleRegistry.Handler]
  package var appearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration]
  package var disappearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration]
  package var changeRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration]

  package init(
    appearHandlers: [String: LocalLifecycleRegistry.Handler] = [:],
    disappearHandlers: [String: LocalLifecycleRegistry.Handler] = [:],
    changeHandlers: [String: LocalLifecycleRegistry.Handler] = [:],
    appearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:],
    disappearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:],
    changeRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  ) {
    self.appearRegistrations =
      appearRegistrations.isEmpty
      ? Self.legacyRegistrations(handlersByID: appearHandlers)
      : appearRegistrations
    self.disappearRegistrations =
      disappearRegistrations.isEmpty
      ? Self.legacyRegistrations(handlersByID: disappearHandlers)
      : disappearRegistrations
    self.changeRegistrations =
      changeRegistrations.isEmpty
      ? Self.legacyRegistrations(handlersByID: changeHandlers)
      : changeRegistrations
    self.appearHandlers = Self.handlersByID(self.appearRegistrations)
    self.disappearHandlers = Self.handlersByID(self.disappearRegistrations)
    self.changeHandlers = Self.handlersByID(self.changeRegistrations)
  }

  package var isEmpty: Bool {
    appearRegistrations.isEmpty
      && disappearRegistrations.isEmpty
      && changeRegistrations.isEmpty
  }

  package mutating func recordAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    appearRegistrations[registration.key] = registration
    appearHandlers[registration.handlerID] = registration.handler
  }

  package mutating func recordDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    disappearRegistrations[registration.key] = registration
    disappearHandlers[registration.handlerID] = registration.handler
  }

  package mutating func recordChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    changeRegistrations[registration.key] = registration
    changeHandlers[registration.handlerID] = registration.handler
  }

  /// Merges a departing node's lifecycle registrations into this snapshot,
  /// keeping this snapshot's own entries on key collisions. Counterpart of
  /// ``NodeHandlers/absorbAdopted(_:)`` for the absorbed-shadowed-node
  /// reclaim (see `ViewGraph.pruneAbsorbedShadowedNodes`).
  package mutating func absorbAdopted(_ departing: LifecycleHandlerSnapshot) {
    appearRegistrations.merge(departing.appearRegistrations) { current, _ in current }
    disappearRegistrations.merge(departing.disappearRegistrations) { current, _ in current }
    changeRegistrations.merge(departing.changeRegistrations) { current, _ in current }
    appearHandlers.merge(departing.appearHandlers) { current, _ in current }
    disappearHandlers.merge(departing.disappearHandlers) { current, _ in current }
    changeHandlers.merge(departing.changeHandlers) { current, _ in current }
  }

  private static func legacyRegistrations(
    handlersByID: [String: LocalLifecycleRegistry.Handler]
  ) -> [LifecycleHandlerKey: LifecycleHandlerRegistration] {
    Dictionary(
      uniqueKeysWithValues: handlersByID.map { handlerID, handler in
        let suffix = LifecycleHandlerKeySuffix.legacy(handlerID)
        let key = LifecycleHandlerKey(
          ownerNodeID: nil,
          suffix: suffix
        )
        return (
          key,
          LifecycleHandlerRegistration(
            identity: lifecycleHandlerIdentity(from: handlerID),
            key: key,
            handlerID: handlerID,
            handler: handler
          )
        )
      }
    )
  }

  private static func handlersByID(
    _ registrations: [LifecycleHandlerKey: LifecycleHandlerRegistration]
  ) -> [String: LocalLifecycleRegistry.Handler] {
    Dictionary(
      registrations.values.map { ($0.handlerID, $0.handler) },
      uniquingKeysWith: { _, latest in latest }
    )
  }
}

@MainActor
package final class LocalLifecycleRegistry: Equatable {
  package typealias Handler = @MainActor @Sendable () -> Void

  private var appearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  private var disappearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  private var changeRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]

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
    let registration = legacyRegistration(
      handlerID: handlerID,
      handler: handler
    )
    recordAppear(registration)
  }

  @discardableResult
  package func registerAppear(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> String {
    let registration = registration(
      identity: identity,
      suffix: .appear(ordinal: ordinal),
      handler: handler
    )
    recordAppear(registration)
    return registration.handlerID
  }

  package func registerDisappear(
    handlerID: String,
    handler: @escaping Handler
  ) {
    let registration = legacyRegistration(
      handlerID: handlerID,
      handler: handler
    )
    recordDisappear(registration)
  }

  @discardableResult
  package func registerDisappear(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> String {
    let registration = registration(
      identity: identity,
      suffix: .disappear(ordinal: ordinal),
      handler: handler
    )
    recordDisappear(registration)
    return registration.handlerID
  }

  package func registerChange(
    handlerID: String,
    handler: @escaping Handler
  ) {
    let registration = legacyRegistration(
      handlerID: handlerID,
      handler: handler
    )
    recordChange(registration)
  }

  @discardableResult
  package func registerChange(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> String {
    let registration = registration(
      identity: identity,
      suffix: .change(ordinal: ordinal),
      handler: handler
    )
    recordChange(registration)
    return registration.handlerID
  }

  package func appearHandler(
    for handlerID: String
  ) -> Handler? {
    appearRegistrations.values.first { $0.handlerID == handlerID }?.handler
  }

  package func disappearHandler(
    for handlerID: String
  ) -> Handler? {
    disappearRegistrations.values.first { $0.handlerID == handlerID }?.handler
  }

  package func changeHandler(
    for handlerID: String
  ) -> Handler? {
    changeRegistrations.values.first { $0.handlerID == handlerID }?.handler
  }

  package func reset() {
    appearRegistrations.removeAll(keepingCapacity: true)
    disappearRegistrations.removeAll(keepingCapacity: true)
    changeRegistrations.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    removeSubtrees(rootedAt: roots, from: &appearRegistrations)
    removeSubtrees(rootedAt: roots, from: &disappearRegistrations)
    removeSubtrees(rootedAt: roots, from: &changeRegistrations)
  }

  package func snapshot() -> LifecycleHandlerSnapshot {
    .init(
      appearRegistrations: appearRegistrations,
      disappearRegistrations: disappearRegistrations,
      changeRegistrations: changeRegistrations
    )
  }

  package func restore(
    _ snapshot: LifecycleHandlerSnapshot
  ) {
    guard
      !snapshot.appearHandlers.isEmpty
        || !snapshot.disappearHandlers.isEmpty
        || !snapshot.changeHandlers.isEmpty
    else {
      return
    }

    for registration in snapshot.appearRegistrations.values {
      appearRegistrations[registration.key] = registration
    }
    for registration in snapshot.disappearRegistrations.values {
      disappearRegistrations[registration.key] = registration
    }
    for registration in snapshot.changeRegistrations.values {
      changeRegistrations[registration.key] = registration
    }
  }

  private func recordAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    appearRegistrations[registration.key] = registration
    ViewNodeContext.current?.recordLifecycleAppearRegistration(registration)
  }

  private func recordDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    disappearRegistrations[registration.key] = registration
    ViewNodeContext.current?.recordLifecycleDisappearRegistration(registration)
  }

  private func recordChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    changeRegistrations[registration.key] = registration
    ViewNodeContext.current?.recordLifecycleChangeRegistration(registration)
  }

  private func registration(
    identity: Identity,
    suffix: LifecycleHandlerKeySuffix,
    handler: @escaping Handler
  ) -> LifecycleHandlerRegistration {
    let key = LifecycleHandlerKey(
      ownerNodeID: ViewNodeContext.current?.viewNodeID,
      suffix: suffix
    )
    return LifecycleHandlerRegistration(
      identity: identity,
      key: key,
      handler: handler
    )
  }

  private func legacyRegistration(
    handlerID: String,
    handler: @escaping Handler
  ) -> LifecycleHandlerRegistration {
    let key = LifecycleHandlerKey(
      ownerNodeID: ViewNodeContext.current?.viewNodeID,
      suffix: .legacy(handlerID)
    )
    return LifecycleHandlerRegistration(
      identity: lifecycleHandlerIdentity(from: handlerID),
      key: key,
      handlerID: handlerID,
      handler: handler
    )
  }

  private func removeSubtrees(
    rootedAt roots: [Identity],
    from registrations: inout [LifecycleHandlerKey: LifecycleHandlerRegistration]
  ) {
    registrations = registrations.filter { _, registration in
      !identityMatchesAnySubtreeRoot(
        registration.identity,
        roots: roots
      )
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
