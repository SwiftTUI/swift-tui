package struct FocusedValuesRegistrationSnapshot: Sendable {
  package var identity: Identity
  package var descendantIdentities: Set<Identity>
  package var values: FocusedValues

  package init(
    identity: Identity,
    descendantIdentities: Set<Identity>,
    values: FocusedValues
  ) {
    self.identity = identity
    self.descendantIdentities = descendantIdentities
    self.values = values
  }
}

@MainActor
package final class LocalFocusedValuesRegistry: Equatable {
  private var registrations: [FocusedValuesRegistrationSnapshot] = []

  package init() {}

  nonisolated package static func == (
    lhs: LocalFocusedValuesRegistry,
    rhs: LocalFocusedValuesRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    descendantIdentities: Set<Identity>? = nil,
    values: FocusedValues
  ) {
    guard !values.isEmpty else {
      return
    }

    let registration = FocusedValuesRegistrationSnapshot(
      identity: identity,
      descendantIdentities: descendantIdentities ?? [identity],
      values: values
    )

    if let existingIndex = registrations.firstIndex(where: { $0.identity == identity }) {
      registrations[existingIndex].descendantIdentities.formUnion(
        registration.descendantIdentities
      )
      registrations[existingIndex].values.merge(registration.values)
    } else {
      registrations.append(registration)
    }
    ViewNodeContext.current?.recordFocusedValuesRegistration(registration)
  }

  package func focusedValues(
    for focusedIdentity: Identity?
  ) -> FocusedValues {
    guard let focusedIdentity else {
      return .init()
    }

    var merged = FocusedValues()
    let matchingRegistrations = snapshot()
      .filter { registration in
        registration.descendantIdentities.contains(focusedIdentity)
          || registration.identity.isAncestor(of: focusedIdentity)
      }
      .sorted {
        if $0.identity.components.count == $1.identity.components.count {
          return $0.identity < $1.identity
        }
        return $0.identity.components.count < $1.identity.components.count
      }

    for registration in matchingRegistrations {
      merged.merge(registration.values)
    }
    return merged
  }

  package func focusedValues(
    for focusedIdentity: Identity?,
    in resolvedTree: ResolvedNode
  ) -> FocusedValues {
    guard let focusedIdentity,
      let path = resolvedTree.path(to: focusedIdentity)
    else {
      return focusedValues(for: focusedIdentity)
    }

    var registrationsByIdentity: [Identity: FocusedValues] = [:]
    for registration in snapshot() {
      registrationsByIdentity[registration.identity, default: .init()].merge(registration.values)
    }
    var merged = FocusedValues()
    for identity in path {
      if let values = registrationsByIdentity[identity] {
        merged.merge(values)
      }
    }
    return merged
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
      identityMatchesAnySubtreeRoot(
        registration.identity,
        roots: roots
      )
    }
  }

  /// Drops registrations whose publisher identity is absent from the committed
  /// tree.
  ///
  /// `removeSubtrees` prunes by identity-prefix against the re-evaluated
  /// frontier roots, but the scoped restore re-adds registrations via a
  /// structural view-node walk. A publisher whose identity is detached from the
  /// frontier (an exact `.id(_:)` that churns per rebuild) is therefore missed
  /// by removal yet re-appended by restore, so the registry grows unbounded.
  /// This end-of-frame prune closes that gap by intersecting against the freshly
  /// rendered tree — the authoritative live-publisher set, independent of
  /// publication mode. Gated on a non-empty registry so the common
  /// no-focused-values path never walks the tree.
  package func pruneToTreeIdentities(
    in resolvedTree: ResolvedNode
  ) {
    guard !registrations.isEmpty else {
      return
    }

    var liveIdentities: Set<Identity> = []
    for identity in resolvedTree.collectIdentities() {
      liveIdentities.insert(identity)
    }
    registrations.removeAll { registration in
      !liveIdentities.contains(registration.identity)
    }
  }

  package func snapshot() -> [FocusedValuesRegistrationSnapshot] {
    registrations
  }

  package func restore(
    _ snapshot: [FocusedValuesRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    registrations.append(contentsOf: snapshot)
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
