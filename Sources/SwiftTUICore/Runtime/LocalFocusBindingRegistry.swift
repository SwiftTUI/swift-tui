package enum FocusBindingRequest: Equatable, Sendable {
  case none
  case clear
  case focus(Identity)
}

package enum FocusBindingKeySuffix: Hashable, Sendable, CustomStringConvertible {
  case stateSlot(ordinal: Int)
  case local(ObjectIdentifier)
  case legacy(String)

  package var description: String {
    switch self {
    case .stateSlot(let ordinal):
      "FocusState[\(ordinal)]"
    case .local(let identifier):
      "FocusState.local[\(identifier)]"
    case .legacy(let bindingID):
      bindingID
    }
  }
}

package typealias FocusBindingKey = ViewNodeRuntimeKey<FocusBindingKeySuffix>

package struct DefaultFocusScopeRegistrationSnapshot: Equatable, Sendable {
  package var namespace: MatchedGeometryNamespace
  package var identity: Identity
  /// Identity of the ViewNode that recorded this registration (stamped by
  /// `ViewNode.recordDefaultFocus`). `removeSubtrees` matches it in addition
  /// to `identity`: a registration published at a DETACHED identity (an exact
  /// `.id(_:)`) is invisible to identity-prefix removal, while the scoped
  /// restore's structural node walk still re-appends it — without the owner
  /// match the registry stacks one copy per scoped commit.
  package var ownerIdentity: Identity?

  package init(
    namespace: MatchedGeometryNamespace,
    identity: Identity,
    ownerIdentity: Identity? = nil
  ) {
    self.namespace = namespace
    self.identity = identity
    self.ownerIdentity = ownerIdentity
  }
}

package struct DefaultFocusCandidateRegistrationSnapshot: Equatable, Sendable {
  package var namespace: MatchedGeometryNamespace
  package var identity: Identity
  /// See ``DefaultFocusScopeRegistrationSnapshot/ownerIdentity``.
  package var ownerIdentity: Identity?

  package init(
    namespace: MatchedGeometryNamespace,
    identity: Identity,
    ownerIdentity: Identity? = nil
  ) {
    self.namespace = namespace
    self.identity = identity
    self.ownerIdentity = ownerIdentity
  }
}

package struct DefaultFocusRegistrationSnapshot: Equatable, Sendable {
  package var scopes: [DefaultFocusScopeRegistrationSnapshot]
  package var candidates: [DefaultFocusCandidateRegistrationSnapshot]

  package init(
    scopes: [DefaultFocusScopeRegistrationSnapshot] = [],
    candidates: [DefaultFocusCandidateRegistrationSnapshot] = []
  ) {
    self.scopes = scopes
    self.candidates = candidates
  }
}

@MainActor
package final class LocalDefaultFocusRegistry: Equatable {
  private var scopes: [DefaultFocusScopeRegistrationSnapshot] = []
  private var candidates: [DefaultFocusCandidateRegistrationSnapshot] = []
  private var pendingResetNamespace: MatchedGeometryNamespace?

  package init() {}

  nonisolated package static func == (
    lhs: LocalDefaultFocusRegistry,
    rhs: LocalDefaultFocusRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func registerScope(
    namespace: MatchedGeometryNamespace,
    identity: Identity
  ) {
    let registration = DefaultFocusScopeRegistrationSnapshot(
      namespace: namespace,
      identity: identity
    )
    scopes.append(registration)
    ViewNodeContext.current?.recordDefaultFocus(registration)
  }

  package func registerCandidate(
    namespace: MatchedGeometryNamespace,
    identity: Identity
  ) {
    let registration = DefaultFocusCandidateRegistrationSnapshot(
      namespace: namespace,
      identity: identity
    )
    candidates.append(registration)
    ViewNodeContext.current?.recordDefaultFocus(registration)
  }

  package func requestReset(
    in namespace: MatchedGeometryNamespace
  ) {
    pendingResetNamespace = namespace
  }

  package func desiredFocusRequest(
    focusRegions: [FocusRegion],
    shouldApplyInitialDefault: Bool
  ) -> FocusBindingRequest {
    if let namespace = pendingResetNamespace {
      pendingResetNamespace = nil
      return focusRequest(
        in: namespace,
        focusRegions: focusRegions
      )
    }

    guard shouldApplyInitialDefault else {
      return .none
    }

    for scope in scopes {
      let request = focusRequest(
        in: scope.namespace,
        focusRegions: focusRegions
      )
      if request != .none {
        return request
      }
    }

    for candidate in candidates
    where focusRegions.contains(where: { $0.identity == candidate.identity }) {
      return .focus(candidate.identity)
    }

    return .none
  }

  package func reset() {
    scopes.removeAll(keepingCapacity: true)
    candidates.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    scopes.removeAll { registration in
      focusRegistrationMatchesAnySubtreeRoot(
        identity: registration.identity,
        ownerIdentity: registration.ownerIdentity,
        roots: roots
      )
    }
    candidates.removeAll { registration in
      focusRegistrationMatchesAnySubtreeRoot(
        identity: registration.identity,
        ownerIdentity: registration.ownerIdentity,
        roots: roots
      )
    }
  }

  package func snapshot() -> DefaultFocusRegistrationSnapshot {
    DefaultFocusRegistrationSnapshot(
      scopes: scopes,
      candidates: candidates
    )
  }

  package func restore(
    _ snapshot: DefaultFocusRegistrationSnapshot
  ) {
    scopes.append(contentsOf: snapshot.scopes)
    candidates.append(contentsOf: snapshot.candidates)
  }

  /// Re-sorts the append-ordered scope/candidate lists into canonical
  /// identity order (stable within an identity). A scoped `.subtrees` restore
  /// re-appends the changed subtree's entries at the end; normalizing restores
  /// the same order a full rebuild produces (nodes restored in
  /// `liveIdentities.sorted()` order), so default-focus resolution — which
  /// returns the first matching candidate — is byte-identical regardless of
  /// which subtree was invalidated.
  package func normalizeOrderByIdentity() {
    scopes = Self.stableSortedByIdentity(scopes, by: \.identity)
    candidates = Self.stableSortedByIdentity(candidates, by: \.identity)
  }

  private static func stableSortedByIdentity<Element>(
    _ elements: [Element],
    by identity: (Element) -> Identity
  ) -> [Element] {
    elements.enumerated()
      .sorted { lhs, rhs in
        let lhsIdentity = identity(lhs.element)
        let rhsIdentity = identity(rhs.element)
        if lhsIdentity != rhsIdentity {
          return lhsIdentity < rhsIdentity
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  private func focusRequest(
    in namespace: MatchedGeometryNamespace,
    focusRegions: [FocusRegion]
  ) -> FocusBindingRequest {
    let regionByIdentity = Dictionary(
      uniqueKeysWithValues: focusRegions.map { ($0.identity, $0) }
    )
    let scopeIdentities =
      scopes
      .filter { $0.namespace == namespace }
      .map(\.identity)

    for candidate in candidates where candidate.namespace == namespace {
      guard let region = regionByIdentity[candidate.identity] else {
        continue
      }
      guard
        scopeIdentities.isEmpty
          || scopeIdentities.contains(where: { scope in
            region.identity == scope
              || region.identity.isDescendant(of: scope)
              || region.scopePath.contains(scope)
          })
      else {
        continue
      }
      return .focus(candidate.identity)
    }

    for scope in scopeIdentities {
      if let fallback = focusRegions.first(where: { region in
        region.identity == scope
          || region.identity.isDescendant(of: scope)
          || region.scopePath.contains(scope)
      }) {
        return .focus(fallback.identity)
      }
    }

    return .none
  }
}

package struct FocusBindingRegistrationSnapshot: Sendable {
  package var identity: Identity
  package var bindingKey: FocusBindingKey
  package var bindingID: String
  package var hasPendingRequest: Bool
  package var isSelected: Bool
  package var applyRuntimeFocus: @MainActor @Sendable (Bool) -> Bool
  /// See ``DefaultFocusScopeRegistrationSnapshot/ownerIdentity``.
  package var ownerIdentity: Identity?

  package init(
    identity: Identity,
    bindingKey: FocusBindingKey,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    ownerIdentity: Identity? = nil,
    applyRuntimeFocus: @escaping @MainActor @Sendable (Bool) -> Bool
  ) {
    self.identity = identity
    self.bindingKey = bindingKey
    self.bindingID = bindingID
    self.hasPendingRequest = hasPendingRequest
    self.isSelected = isSelected
    self.ownerIdentity = ownerIdentity
    self.applyRuntimeFocus = applyRuntimeFocus
  }

  package init(
    identity: Identity,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    applyRuntimeFocus: @escaping @MainActor @Sendable (Bool) -> Bool
  ) {
    self.init(
      identity: identity,
      bindingKey: FocusBindingKey(
        ownerNodeID: nil,
        suffix: .legacy(bindingID)
      ),
      bindingID: bindingID,
      hasPendingRequest: hasPendingRequest,
      isSelected: isSelected,
      applyRuntimeFocus: applyRuntimeFocus
    )
  }
}

@MainActor
package final class LocalFocusBindingRegistry: Equatable {
  private var registrations: [FocusBindingRegistrationSnapshot] = []

  package init() {}

  nonisolated package static func == (
    lhs: LocalFocusBindingRegistry,
    rhs: LocalFocusBindingRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    bindingKey: FocusBindingKey,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    applyRuntimeFocus: @escaping @MainActor @Sendable (Bool) -> Bool
  ) {
    let registration = FocusBindingRegistrationSnapshot(
      identity: identity,
      bindingKey: bindingKey,
      bindingID: bindingID,
      hasPendingRequest: hasPendingRequest,
      isSelected: isSelected,
      applyRuntimeFocus: applyRuntimeFocus
    )
    registrations.append(registration)
    ViewNodeContext.current?.recordFocusBindingRegistration(registration)
  }

  package func register(
    identity: Identity,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    applyRuntimeFocus: @escaping @MainActor @Sendable (Bool) -> Bool
  ) {
    register(
      identity: identity,
      bindingKey: FocusBindingKey(
        ownerNodeID: nil,
        suffix: .legacy(bindingID)
      ),
      bindingID: bindingID,
      hasPendingRequest: hasPendingRequest,
      isSelected: isSelected,
      applyRuntimeFocus: applyRuntimeFocus
    )
  }

  package func desiredFocusRequest(
    allowedIdentities: Set<Identity>
  ) -> FocusBindingRequest {
    let snapshot = self.snapshot()
    var seenBindingKeys: Set<FocusBindingKey> = []

    for registration in snapshot {
      guard seenBindingKeys.insert(registration.bindingKey).inserted else {
        continue
      }

      let matching = snapshot.filter { $0.bindingKey == registration.bindingKey }
      guard matching.contains(where: \.hasPendingRequest) else {
        continue
      }

      if let selected = matching.first(where: \.isSelected) {
        if allowedIdentities.contains(selected.identity) {
          return .focus(selected.identity)
        }
        return .none
      }

      return .clear
    }

    return .none
  }

  package func sync(
    actualFocusedIdentity: Identity?
  ) -> Bool {
    let snapshot = self.snapshot()
    let grouped = orderedGroups(from: snapshot)
    var changed = false

    for group in grouped {
      for registration in group where registration.identity != actualFocusedIdentity {
        changed = registration.applyRuntimeFocus(false) || changed
      }
      if let actualFocusedIdentity,
        let selected = group.first(where: { $0.identity == actualFocusedIdentity })
      {
        changed = selected.applyRuntimeFocus(true) || changed
      }
    }

    return changed
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    registrations.removeAll { registration in
      focusRegistrationMatchesAnySubtreeRoot(
        identity: registration.identity,
        ownerIdentity: registration.ownerIdentity,
        roots: roots
      )
    }
  }

  package func snapshot() -> [FocusBindingRegistrationSnapshot] {
    registrations
  }

  package func restore(
    _ snapshot: [FocusBindingRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    registrations.append(contentsOf: snapshot)
  }

  /// Re-sorts the append-ordered registration list into canonical identity
  /// order (stable within an identity), matching a full rebuild's order after a
  /// scoped `.subtrees` restore. See
  /// ``LocalDefaultFocusRegistry/normalizeOrderByIdentity()``.
  package func normalizeOrderByIdentity() {
    registrations =
      registrations.enumerated()
      .sorted { lhs, rhs in
        if lhs.element.identity != rhs.element.identity {
          return lhs.element.identity < rhs.element.identity
        }
        return lhs.offset < rhs.offset
      }
      .map(\.element)
  }

  private func orderedGroups(
    from snapshot: [FocusBindingRegistrationSnapshot]
  ) -> [[FocusBindingRegistrationSnapshot]] {
    var grouped: [FocusBindingKey: [FocusBindingRegistrationSnapshot]] = [:]
    var orderedBindingKeys: [FocusBindingKey] = []

    for registration in snapshot {
      if grouped[registration.bindingKey] == nil {
        orderedBindingKeys.append(registration.bindingKey)
        grouped[registration.bindingKey] = []
      }
      grouped[registration.bindingKey]?.append(registration)
    }

    return orderedBindingKeys.compactMap { grouped[$0] }
  }
}

/// Matches a focus registration against subtree-removal roots by its
/// registered identity AND by the identity of the node that recorded it. The
/// owner match is what clears registrations published at detached identities
/// (an exact `.id(_:)`) when their publisher is re-evaluated — the scoped
/// restore re-appends the publisher's snapshots, so a removal that misses
/// them stacks one copy per scoped commit.
package func focusRegistrationMatchesAnySubtreeRoot(
  identity: Identity,
  ownerIdentity: Identity?,
  roots: [Identity]
) -> Bool {
  roots.contains { root in
    identity == root || identity.isDescendant(of: root)
      || ownerIdentity == root
      || ownerIdentity?.isDescendant(of: root) == true
  }
}
