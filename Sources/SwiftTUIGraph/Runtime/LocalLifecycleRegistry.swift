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

package struct LifecycleHandlerRegistration: Sendable {
  package var identity: Identity
  package var key: LifecycleHandlerKey
  package var handlerID: String
  package var handler: LocalLifecycleRegistry.Handler
  /// Monotonic registration order within one registry, stamped at record
  /// time. Two owners minting the same handlerID string (one identity +
  /// ordinal registered by two nodes) collapse deterministically to the
  /// LATEST registration wherever a string-keyed view is built (F130) —
  /// the previous dictionary-order collapse was nondeterministic.
  package var recency: UInt64

  package init(
    identity: Identity,
    key: LifecycleHandlerKey,
    handlerID: String? = nil,
    recency: UInt64 = 0,
    handler: @escaping LocalLifecycleRegistry.Handler
  ) {
    self.identity = identity
    self.key = key
    self.handlerID = handlerID ?? "\(identity)#\(key.suffix)"
    self.recency = recency
    self.handler = handler
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
    appearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:],
    disappearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:],
    changeRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  ) {
    self.appearRegistrations = appearRegistrations
    self.disappearRegistrations = disappearRegistrations
    self.changeRegistrations = changeRegistrations
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

  private static func handlersByID(
    _ registrations: [LifecycleHandlerKey: LifecycleHandlerRegistration]
  ) -> [String: LocalLifecycleRegistry.Handler] {
    // Two owners at one identity+ordinal share a handlerID string; the
    // LATEST registration wins deterministically (dictionary-order
    // uniquing was nondeterministic — F130).
    var winners: [String: LifecycleHandlerRegistration] = [:]
    for registration in registrations.values {
      if let current = winners[registration.handlerID],
        current.recency >= registration.recency
      {
        continue
      }
      winners[registration.handlerID] = registration
    }
    return winners.mapValues(\.handler)
  }
}

@MainActor
package final class LocalLifecycleRegistry: Equatable {
  package typealias Handler = @MainActor @Sendable () -> Void

  private var appearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  private var disappearRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  private var changeRegistrations: [LifecycleHandlerKey: LifecycleHandlerRegistration] = [:]
  /// String handlerID → the LATEST registration's typed key, maintained at
  /// every mutation so dispatch is a dictionary lookup instead of an O(n)
  /// value scan (F130). Shared across the three kinds: handlerIDs embed
  /// their suffix, so the namespaces cannot collide.
  private var handlerKeysByID: [String: LifecycleHandlerKey] = [:]
  /// Monotonic registration order, stamped onto each registration so
  /// same-handlerID collisions collapse deterministically to the latest.
  private var nextRegistrationRecency: UInt64 = 0

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
  ) -> String {
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
  ) -> String {
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
    handlerKeysByID[handlerID].flatMap { appearRegistrations[$0]?.handler }
  }

  package func disappearHandler(
    for handlerID: String
  ) -> Handler? {
    handlerKeysByID[handlerID].flatMap { disappearRegistrations[$0]?.handler }
  }

  package func changeHandler(
    for handlerID: String
  ) -> Handler? {
    handlerKeysByID[handlerID].flatMap { changeRegistrations[$0]?.handler }
  }

  package func reset() {
    appearRegistrations.removeAll(keepingCapacity: true)
    disappearRegistrations.removeAll(keepingCapacity: true)
    changeRegistrations.removeAll(keepingCapacity: true)
    handlerKeysByID.removeAll(keepingCapacity: true)
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
    rebuildHandlerIDIndex()
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
    rebuildHandlerIDIndex()
  }

  /// Rebuilds the string index from every surviving registration, latest
  /// recency winning. Runs on the non-hot mutation paths (teardown,
  /// restore); per-record maintenance covers the hot registration path.
  private func rebuildHandlerIDIndex() {
    handlerKeysByID.removeAll(keepingCapacity: true)
    var winners: [String: UInt64] = [:]
    for registrations in [appearRegistrations, disappearRegistrations, changeRegistrations] {
      for registration in registrations.values {
        if let current = winners[registration.handlerID],
          current >= registration.recency
        {
          continue
        }
        winners[registration.handlerID] = registration.recency
        handlerKeysByID[registration.handlerID] = registration.key
      }
    }
  }

  private func recordAppear(
    _ registration: LifecycleHandlerRegistration
  ) {
    appearRegistrations[registration.key] = registration
    handlerKeysByID[registration.handlerID] = registration.key
    ViewNodeContext.current?.recordLifecycleAppearRegistration(registration)
  }

  private func recordDisappear(
    _ registration: LifecycleHandlerRegistration
  ) {
    disappearRegistrations[registration.key] = registration
    handlerKeysByID[registration.handlerID] = registration.key
    ViewNodeContext.current?.recordLifecycleDisappearRegistration(registration)
  }

  private func recordChange(
    _ registration: LifecycleHandlerRegistration
  ) {
    changeRegistrations[registration.key] = registration
    handlerKeysByID[registration.handlerID] = registration.key
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
    // 64-bit wraparound is deliberately unguarded (F122): unreachable in practice, and the recency comparisons assume no value reuse.
    nextRegistrationRecency &+= 1
    return LifecycleHandlerRegistration(
      identity: identity,
      key: key,
      recency: nextRegistrationRecency,
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

