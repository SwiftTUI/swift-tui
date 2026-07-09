package struct RuntimeRegistrationOwnerKey: Hashable, Comparable, Sendable {
  package var viewNodeID: ViewNodeID?
  package var identity: Identity
  package var structuralPath: StructuralPath

  package init(
    viewNodeID: ViewNodeID? = nil,
    identity: Identity,
    structuralPath: StructuralPath? = nil
  ) {
    self.viewNodeID = viewNodeID
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
  }

  @MainActor
  package static func current(identity: Identity) -> Self {
    guard let node = ViewNodeContext.current else {
      return Self(identity: identity)
    }

    return Self(
      viewNodeID: node.viewNodeID,
      identity: identity,
      structuralPath: StructuralPath(identity: identity)
    )
  }

  package func matchesAnySubtreeRoot(
    _ roots: [Identity]
  ) -> Bool {
    roots.contains(where: matchesSubtreeRoot)
  }

  private func matchesSubtreeRoot(
    _ root: Identity
  ) -> Bool {
    if identity == root || identity.isDescendant(of: root) {
      return true
    }

    let structuralIdentity = structuralPath.identityProjection
    return structuralIdentity == root || structuralIdentity.isDescendant(of: root)
  }

  package static func < (
    lhs: RuntimeRegistrationOwnerKey,
    rhs: RuntimeRegistrationOwnerKey
  ) -> Bool {
    if lhs.identity != rhs.identity {
      return lhs.identity < rhs.identity
    }
    switch (lhs.viewNodeID, rhs.viewNodeID) {
    case (.some(let lhsID), .some(let rhsID)):
      if lhsID != rhsID {
        return lhsID < rhsID
      }
    case (.none, .some):
      return true
    case (.some, .none):
      return false
    case (.none, .none):
      break
    }
    return lhs.structuralPath.description < rhs.structuralPath.description
  }
}
