package struct FocusedValuesRegistrationSnapshot: Sendable {
  package var identity: Identity
  package var descendantIdentities: Set<Identity>
  package var values: FocusedValues
  /// See ``DefaultFocusScopeRegistrationSnapshot/ownerIdentity``.
  package var ownerIdentity: Identity?

  package init(
    identity: Identity,
    descendantIdentities: Set<Identity>,
    values: FocusedValues,
    ownerIdentity: Identity? = nil
  ) {
    self.identity = identity
    self.descendantIdentities = descendantIdentities
    self.values = values
    self.ownerIdentity = ownerIdentity
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
      focusRegistrationMatchesAnySubtreeRoot(
        identity: registration.identity,
        ownerIdentity: registration.ownerIdentity,
        roots: roots
      )
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

    // Merge same-identity entries exactly like `register` does (F103): a
    // bare append relied on callers always clearing before restoring, but
    // focus-binding churn restores over a live same-identity entry (caught
    // by the assert this merge replaced). Duplicates were mostly latent —
    // the consumers merge per identity — but a stale copy would still merge
    // its values over the churned entry's.
    for entry in snapshot {
      if let existingIndex = registrations.firstIndex(where: { $0.identity == entry.identity }) {
        registrations[existingIndex].descendantIdentities.formUnion(entry.descendantIdentities)
        registrations[existingIndex].values.merge(entry.values)
      } else {
        registrations.append(entry)
      }
    }
  }
}
