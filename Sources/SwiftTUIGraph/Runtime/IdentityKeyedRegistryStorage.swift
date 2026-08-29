/// The single-map lifecycle every semantics-free identity-keyed runtime
/// registry repeats (F102 tier 1): last-write-wins values keyed by
/// `Identity`, a paired `RuntimeRegistrationOwnerKey` companion map, and the
/// shared reset / removeSubtrees / snapshot / restore contract that
/// `RuntimeRegistryLifecycleParameterizedTests` pins family-wide.
///
/// Registries hold one by **composition** and keep their dispatch semantics
/// inline — the store owns storage and lifecycle only. Deliberately not
/// adopted by: `LocalKeyHandlerRegistry` (one owner map shared across three
/// sub-families with bespoke contributed-bucket pruning) and the
/// gesture/pointer family (node-liveness-coupled state whose prune
/// exceptions are quarantined behind the F100/F101 characterization tests).
@MainActor
package struct IdentityKeyedRegistryStorage<Value> {
  package private(set) var values: [Identity: Value]
  package private(set) var ownersByIdentity: [Identity: RuntimeRegistrationOwnerKey]

  package init() {
    values = [:]
    ownersByIdentity = [:]
  }

  package subscript(identity: Identity) -> Value? {
    values[identity]
  }

  /// Sets `value` for `identity` and stamps its owner. Last write wins —
  /// the family contract (see the F104 duplicate-registration alarm for the
  /// collision diagnostic, which lives at the record-intake layer).
  package mutating func set(
    _ value: Value,
    for identity: Identity,
    owner: RuntimeRegistrationOwnerKey
  ) {
    values[identity] = value
    ownersByIdentity[identity] = owner
  }

  package mutating func reset() {
    values.removeAll(keepingCapacity: true)
    ownersByIdentity.removeAll(keepingCapacity: true)
  }

  /// Removes every entry whose owner sits under any of `roots`, falling
  /// back to an identity-derived owner for entries restored without one.
  package mutating func removeSubtrees(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else {
      return
    }

    for identity in values.keys.filter({
      (ownersByIdentity[$0] ?? .init(identity: $0)).matchesAnySubtreeRoot(roots)
    }) {
      values.removeValue(forKey: identity)
      ownersByIdentity.removeValue(forKey: identity)
    }
  }

  /// Drops every entry that `isJustified` rejects (F04).
  ///
  /// The caller's predicate asks the entry's OWNER NODE whether it still
  /// records this registration. That is the node axis of teardown, and it is
  /// the one ``removeSubtrees(rootedAt:)`` above cannot see: that selects on
  /// the registration KEY's identity prefix, so an entry whose identity sits
  /// outside the removed roots survives however dead it is. Both halves of
  /// the measured residual are that gap — a departed owner's entry standing
  /// after its node is gone, and a live owner's entry standing after it
  /// stopped recording it.
  package mutating func removeUnjustified(
    _ isJustified: (Identity, RuntimeRegistrationOwnerKey) -> Bool
  ) {
    for (identity, owner) in ownersByIdentity
    where values[identity] != nil && !isJustified(identity, owner) {
      values.removeValue(forKey: identity)
      ownersByIdentity.removeValue(forKey: identity)
    }
  }

  /// Overlays `snapshot` onto the live map (replace-per-identity), taking
  /// each restored entry's owner from `restoredOwners` when present and
  /// deriving it from the identity otherwise. Empty snapshots are a no-op
  /// (the F105 family guard).
  package mutating func restore(
    _ snapshot: [Identity: Value],
    ownersByIdentity restoredOwners: [Identity: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (identity, value) in snapshot {
      values[identity] = value
      ownersByIdentity[identity] = restoredOwners[identity] ?? .init(identity: identity)
    }
  }
}
