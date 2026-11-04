package enum LifecycleHandlerKeySuffix: Hashable, Sendable, CustomStringConvertible {
  case appear(ordinal: Int)
  case disappear(ordinal: Int)
  case change(ordinal: Int)

  package var description: String {
    switch self {
    case .appear(let ordinal):
      "appear[\(ordinal)]"
    case .disappear(let ordinal):
      "disappear[\(ordinal)]"
    case .change(let ordinal):
      "change[\(ordinal)]"
    }
  }
}

package typealias LifecycleHandlerKey = ViewNodeRuntimeKey<LifecycleHandlerKeySuffix>

package enum LifecycleHandlerID: Hashable, Sendable, CustomStringConvertible,
  ExpressibleByStringLiteral
{
  case registered(identity: Identity, key: LifecycleHandlerKey)
  case legacy(String)

  package init(stringLiteral value: String) { self = .legacy(value) }

  @MainActor package static func current(_ identity: Identity, _ suffix: LifecycleHandlerKeySuffix)
    -> Self
  {
    .registered(
      identity: identity,
      key: .init(ownerNodeID: ViewNodeContext.current?.viewNodeID, suffix: suffix))
  }

  package var description: String {
    switch self {
    case .registered(let identity, let key): "\(identity)#\(key.suffix)"
    case .legacy(let label): label
    }
  }
}

package struct LifecycleHandlerRegistration: Sendable {
  package let identity: Identity
  package let handlerID: LifecycleHandlerID
  package let handler: LocalLifecycleRegistry.Handler

  package init(
    identity: Identity, key: LifecycleHandlerKey, handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    self.identity = identity
    self.handlerID = .registered(identity: identity, key: key)
    self.handler = handler
  }
}

package struct LifecycleHandlerSnapshot: Sendable {
  package var appearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration]
  package var disappearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration]
  package var changeRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration]

  package init(
    appearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:],
    disappearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:],
    changeRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:]
  ) {
    self.appearRegistrations = appearRegistrations
    self.disappearRegistrations = disappearRegistrations
    self.changeRegistrations = changeRegistrations
  }

  package var isEmpty: Bool {
    appearRegistrations.isEmpty
      && disappearRegistrations.isEmpty
      && changeRegistrations.isEmpty
  }

  package mutating func recordAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    appearRegistrations[registration.handlerID] = registration
  }

  package mutating func recordDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    disappearRegistrations[registration.handlerID] = registration
  }

  package mutating func recordChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    changeRegistrations[registration.handlerID] = registration
  }

  /// Overlays `newer`'s registrations onto this snapshot, letting the newer
  /// entries win on collisions. Used by the lifecycle coordinator's retained
  /// handler store: content that re-registers replaces its retained entry,
  /// content that reuses without re-registering keeps the last-committed one.
  package mutating func absorbNewer(_ newer: LifecycleHandlerSnapshot) {
    guard !newer.isEmpty else {
      return
    }
    appearRegistrations.merge(newer.appearRegistrations) { _, newer in newer }
    disappearRegistrations.merge(newer.disappearRegistrations) { _, newer in newer }
    changeRegistrations.merge(newer.changeRegistrations) { _, newer in newer }
  }

  /// Drops every registration whose identity sits at or below one of
  /// `identities`. Used by the lifecycle coordinator's retained handler
  /// store when a subtree's disappear dispatches — the framework's own
  /// departure signal — so retention stays bounded by live content.
  package mutating func prune(under identities: [Identity]) {
    guard !identities.isEmpty else {
      return
    }
    func matches(_ registration: LifecycleHandlerRegistration) -> Bool {
      identities.contains { root in
        registration.identity == root || registration.identity.isDescendant(of: root)
      }
    }
    appearRegistrations = appearRegistrations.filter { !matches($0.value) }
    disappearRegistrations = disappearRegistrations.filter { !matches($0.value) }
    changeRegistrations = changeRegistrations.filter { !matches($0.value) }
  }

  /// Merges a departing node's lifecycle registrations into this snapshot,
  /// keeping this snapshot's own entries on key collisions. Counterpart of
  /// ``NodeHandlers/absorbAdopted(_:)`` for the absorbed-shadowed-node
  /// reclaim (see `ViewGraph.pruneAbsorbedShadowedNodes`).
  package mutating func absorbAdopted(_ departing: LifecycleHandlerSnapshot) {
    appearRegistrations.merge(departing.appearRegistrations) { current, _ in current }
    disappearRegistrations.merge(departing.disappearRegistrations) { current, _ in current }
    changeRegistrations.merge(departing.changeRegistrations) { current, _ in current }
  }

  /// Public metadata created with the older string initializer can still name a
  /// unique registration. A label shared by two owners cannot identify either one.
  fileprivate static func handler(
    for id: LifecycleHandlerID,
    in registrations: [LifecycleHandlerID: LifecycleHandlerRegistration]
  ) -> LocalLifecycleRegistry.Handler? {
    if case .legacy(let label) = id {
      var matches = registrations.values.lazy.filter { $0.handlerID.description == label }
        .makeIterator()
      guard let match = matches.next(), matches.next() == nil else { return nil }
      return match.handler
    }
    return registrations[id]?.handler
  }

  package func appearHandler(for id: LifecycleHandlerID) -> LocalLifecycleRegistry.Handler? {
    Self.handler(for: id, in: appearRegistrations)
  }
  package func disappearHandler(for id: LifecycleHandlerID) -> LocalLifecycleRegistry.Handler? {
    Self.handler(for: id, in: disappearRegistrations)
  }
  package func changeHandler(for id: LifecycleHandlerID) -> LocalLifecycleRegistry.Handler? {
    Self.handler(for: id, in: changeRegistrations)
  }

}

@MainActor
package final class LocalLifecycleRegistry: Equatable {
  package typealias Handler = @MainActor @Sendable () -> Void

  private var appearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:]
  private var disappearRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:]
  private var changeRegistrations: [LifecycleHandlerID: LifecycleHandlerRegistration] = [:]
  package init() {}

  nonisolated package static func == (
    lhs: LocalLifecycleRegistry,
    rhs: LocalLifecycleRegistry
  ) -> Bool {
    lhs === rhs
  }

  @discardableResult
  package func registerAppear(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> LifecycleHandlerID {
    let registration = registration(
      identity: identity,
      suffix: .appear(ordinal: ordinal),
      handler: handler
    )
    recordAppear(registration)
    return registration.handlerID
  }

  @discardableResult
  package func registerDisappear(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> LifecycleHandlerID {
    let registration = registration(
      identity: identity,
      suffix: .disappear(ordinal: ordinal),
      handler: handler
    )
    recordDisappear(registration)
    return registration.handlerID
  }

  @discardableResult
  package func registerChange(
    identity: Identity,
    ordinal: Int,
    handler: @escaping Handler
  ) -> LifecycleHandlerID {
    let registration = registration(
      identity: identity,
      suffix: .change(ordinal: ordinal),
      handler: handler
    )
    recordChange(registration)
    return registration.handlerID
  }

  package func appearHandler(
    for handlerID: LifecycleHandlerID
  ) -> Handler? {
    LifecycleHandlerSnapshot.handler(for: handlerID, in: appearRegistrations)
  }

  package func disappearHandler(
    for handlerID: LifecycleHandlerID
  ) -> Handler? {
    LifecycleHandlerSnapshot.handler(for: handlerID, in: disappearRegistrations)
  }

  package func changeHandler(
    for handlerID: LifecycleHandlerID
  ) -> Handler? {
    LifecycleHandlerSnapshot.handler(for: handlerID, in: changeRegistrations)
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
    guard !snapshot.isEmpty else { return }

    for registration in snapshot.appearRegistrations.values {
      appearRegistrations[registration.handlerID] = registration
    }
    for registration in snapshot.disappearRegistrations.values {
      disappearRegistrations[registration.handlerID] = registration
    }
    for registration in snapshot.changeRegistrations.values {
      changeRegistrations[registration.handlerID] = registration
    }
  }

  private func recordAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    appearRegistrations[registration.handlerID] = registration
    ViewNodeContext.current?.recordLifecycleAppearRegistration(registration)
  }

  private func recordDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    disappearRegistrations[registration.handlerID] = registration
    ViewNodeContext.current?.recordLifecycleDisappearRegistration(registration)
  }

  private func recordChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    changeRegistrations[registration.handlerID] = registration
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

  private func removeSubtrees(
    rootedAt roots: [Identity],
    from registrations: inout [LifecycleHandlerID: LifecycleHandlerRegistration]
  ) {
    registrations = registrations.filter { _, registration in
      !identityMatchesAnySubtreeRoot(
        registration.identity,
        roots: roots
      )
    }
  }
}
