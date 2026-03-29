package enum FocusBindingRequest: Equatable, Sendable {
  case none
  case clear
  case focus(Identity)
}

// SAFETY: Contains a non-Sendable closure `applyRuntimeFocus: (Bool) -> Bool`. This closure
// captures @MainActor state and is only invoked on @MainActor during the focus sync phase.
// Only transferred between the registry and RetainedResolveFrame on the same actor.
package struct FocusBindingRegistrationSnapshot: @unchecked Sendable {
  package var identity: Identity
  package var bindingID: String
  package var hasPendingRequest: Bool
  package var isSelected: Bool
  package var applyRuntimeFocus: (Bool) -> Bool

  package init(
    identity: Identity,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    applyRuntimeFocus: @escaping (Bool) -> Bool
  ) {
    self.identity = identity
    self.bindingID = bindingID
    self.hasPendingRequest = hasPendingRequest
    self.isSelected = isSelected
    self.applyRuntimeFocus = applyRuntimeFocus
  }
}

// SAFETY: Created and exclusively accessed on @MainActor during resolve/event phases.
// Contains non-Sendable closures via FocusBindingRegistrationSnapshot.
// All mutable state protected by OSAllocatedUnfairLock.
package final class LocalFocusBindingRegistry: @unchecked Sendable, Equatable {
  private struct Storage {
    var registrations: [FocusBindingRegistrationSnapshot] = []
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  package init() {}

  package static func == (
    lhs: LocalFocusBindingRegistry,
    rhs: LocalFocusBindingRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    bindingID: String,
    hasPendingRequest: Bool,
    isSelected: Bool,
    applyRuntimeFocus: @escaping (Bool) -> Bool
  ) {
    storage.withLockUnchecked { storage in
      storage.registrations.append(
        .init(
          identity: identity,
          bindingID: bindingID,
          hasPendingRequest: hasPendingRequest,
          isSelected: isSelected,
          applyRuntimeFocus: applyRuntimeFocus
        )
      )
    }
  }

  package func desiredFocusRequest(
    allowedIdentities: Set<Identity>
  ) -> FocusBindingRequest {
    let snapshot = self.snapshot()
    var seenBindingIDs: Set<String> = []

    for registration in snapshot {
      guard seenBindingIDs.insert(registration.bindingID).inserted else {
        continue
      }

      let matching = snapshot.filter { $0.bindingID == registration.bindingID }
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
    storage.withLockUnchecked { storage in
      storage.registrations.removeAll(keepingCapacity: true)
    }
  }

  package func snapshot() -> [FocusBindingRegistrationSnapshot] {
    storage.withLockUnchecked { storage in
      storage.registrations
    }
  }

  package func restore(
    _ snapshot: [FocusBindingRegistrationSnapshot]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    storage.withLock { storage in
      storage.registrations.append(contentsOf: snapshot)
    }
  }

  private func orderedGroups(
    from snapshot: [FocusBindingRegistrationSnapshot]
  ) -> [[FocusBindingRegistrationSnapshot]] {
    var grouped: [String: [FocusBindingRegistrationSnapshot]] = [:]
    var orderedBindingIDs: [String] = []

    for registration in snapshot {
      if grouped[registration.bindingID] == nil {
        orderedBindingIDs.append(registration.bindingID)
        grouped[registration.bindingID] = []
      }
      grouped[registration.bindingID]?.append(registration)
    }

    return orderedBindingIDs.compactMap { grouped[$0] }
  }
}
