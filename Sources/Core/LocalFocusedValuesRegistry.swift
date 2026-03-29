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

// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// All mutable state protected by OSAllocatedUnfairLock. Contains Sendable data types only,
// but the compiler cannot prove Sendability through the lock's unchecked state parameter.
package final class LocalFocusedValuesRegistry: @unchecked Sendable, Equatable {
  private struct Storage {
    var registrations: [FocusedValuesRegistrationSnapshot] = []
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (
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

    storage.withLockUnchecked { storage in
      let registration = FocusedValuesRegistrationSnapshot(
        identity: identity,
        descendantIdentities: descendantIdentities ?? [identity],
        values: values
      )

      if let existingIndex = storage.registrations.firstIndex(where: { $0.identity == identity }) {
        storage.registrations[existingIndex].descendantIdentities.formUnion(
          registration.descendantIdentities
        )
        storage.registrations[existingIndex].values.merge(registration.values)
      } else {
        storage.registrations.append(registration)
      }
    }
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
    storage.withLockUnchecked { storage in
      storage.registrations.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> [FocusedValuesRegistrationSnapshot] {
    storage.withLockUnchecked { storage in
      storage.registrations
    }
  }

  package func restore(
    _ snapshot: [FocusedValuesRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    storage.withLockUnchecked { storage in
      storage.registrations.append(contentsOf: snapshot)
    }
  }
}
