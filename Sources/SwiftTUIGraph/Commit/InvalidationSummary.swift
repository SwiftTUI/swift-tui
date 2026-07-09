package struct InvalidationSummary: Equatable, Sendable {
  package let directlyInvalidated: Set<Identity>
  package let identitiesWithInvalidatedDescendants: Set<Identity>

  package init(
    invalidatedIdentities: Set<Identity>
  ) {
    directlyInvalidated = invalidatedIdentities

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
    var ancestor = StructuralPath(identity: identity).parent
    while let current = ancestor {
      if directlyInvalidated.contains(current.identityProjection) {
        return true
      }
      ancestor = current.parent
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
