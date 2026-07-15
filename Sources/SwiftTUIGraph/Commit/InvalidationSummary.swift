package struct InvalidationSummary: Equatable, Sendable {
  package let directlyInvalidated: Set<Identity>
  package let identitiesWithInvalidatedDescendants: Set<Identity>
  /// The invalidated identities' component paths, resolved once so the
  /// per-candidate ancestor query below prefix-compares against this (tiny)
  /// list instead of minting an `Identity` per ancestor level per call.
  private let directlyInvalidatedComponents: [[String]]

  package init(
    invalidatedIdentities: Set<Identity>
  ) {
    directlyInvalidated = invalidatedIdentities
    directlyInvalidatedComponents = invalidatedIdentities.map(\.components)

    var identitiesWithInvalidatedDescendants: Set<Identity> = []
    for invalidatedIdentity in invalidatedIdentities {
      // Walk structural ancestry on the `StructuralPath` axis rather than the
      // `Identity` string, so the invalidation engine no longer treats
      // `Identity` as a containment proxy. `StructuralPath(identity:)` is the
      // lossless projection of the runtime identity, so for indexed identities
      // this is behavior-preserving; genuine structural divergence (.id /
      // ForEach / portals) is resolved upstream by the live-graph and
      // `StructuralFrameIndex`-backed classifiers.
      var ancestor = StructuralPath(identity: invalidatedIdentity).parent
      while let current = ancestor {
        identitiesWithInvalidatedDescendants.insert(current.identityProjection)
        ancestor = current.parent
      }
    }
    self.identitiesWithInvalidatedDescendants = identitiesWithInvalidatedDescendants
  }

  package var isEmpty: Bool {
    directlyInvalidated.isEmpty
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    // `directlyInvalidatedComponents` is derived from `directlyInvalidated`
    // in Set-iteration order — comparing it would make equal summaries
    // spuriously unequal. The two identity sets carry all the information.
    lhs.directlyInvalidated == rhs.directlyInvalidated
      && lhs.identitiesWithInvalidatedDescendants == rhs.identitiesWithInvalidatedDescendants
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    directlyInvalidated.contains(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    identitiesWithInvalidatedDescendants.contains(identity)
  }

  package func hasInvalidatedAncestor(
    of identity: Identity
  ) -> Bool {
    // Inverted from the historical per-level ancestor walk: an invalidated
    // identity is a strict ancestor of `identity` exactly when its component
    // path is a strict prefix (`StructuralPath(identity:)` round-trips the
    // component list losslessly, so prefix-on-components equals membership of
    // the projected ancestor identity in the set). Iterating the (tiny)
    // invalidated list avoids minting an `Identity` — plus hashing it — per
    // ancestor level on every reuse-gate query.
    guard !directlyInvalidatedComponents.isEmpty else {
      return false
    }
    let components = identity.components
    for invalidatedComponents in directlyInvalidatedComponents {
      if invalidatedComponents.count < components.count,
        zip(invalidatedComponents, components).allSatisfy(==)
      {
        return true
      }
    }
    return false
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    isDirectlyInvalidated(identity)
      || containsInvalidatedDescendant(of: identity)
      || hasInvalidatedAncestor(of: identity)
  }
}
