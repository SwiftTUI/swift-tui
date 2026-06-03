package struct ChildDescriptor: Hashable, Sendable {
  package var identity: Identity
  package var structuralPath: StructuralPath
  package var typeIdentity: String
  /// Refines the String `typeIdentity` with a stable per-Swift-type
  /// discriminator when one is available.  Two descriptors with the same
  /// `typeIdentity` but different non-nil discriminators are unequal:
  /// this catches accidental kind-name collisions that a String-only
  /// comparison would silently fuse.  When either side is `nil` (legacy
  /// call site or in-progress migration) the comparison falls back to
  /// the String, so partial migrations don't produce structural churn.
  package var typeDiscriminator: ObjectIdentifier?
  package var explicitID: String?

  package init(
    identity: Identity,
    structuralPath: StructuralPath? = nil,
    typeIdentity: String,
    typeDiscriminator: ObjectIdentifier? = nil,
    explicitID: String? = nil
  ) {
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
    self.typeIdentity = typeIdentity
    self.typeDiscriminator = typeDiscriminator
    self.explicitID = explicitID
  }

  package init(resolvedNode: ResolvedNode) {
    identity = resolvedNode.identity
    structuralPath = resolvedNode.structuralPath
    typeIdentity =
      switch resolvedNode.kind {
      case .root:
        "root"
      case .scene(let name):
        "scene:\(name)"
      case .view(let name):
        "view:\(name)"
      }
    typeDiscriminator = resolvedNode.typeDiscriminator
    explicitID = Self.explicitID(from: resolvedNode.identity)
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.structuralPath == rhs.structuralPath,
      lhs.explicitID == rhs.explicitID,
      lhs.typeIdentity == rhs.typeIdentity
    else {
      return false
    }
    return ResolvedNode.typeDiscriminatorsCompatible(
      lhs.typeDiscriminator,
      rhs.typeDiscriminator
    )
  }

  package func hash(into hasher: inout Hasher) {
    // `typeDiscriminator` is deliberately excluded.  A typed descriptor
    // (discriminator non-nil) must hash-equal a legacy descriptor
    // (discriminator nil) with the same String name, because the
    // bridging equality rule treats them as equal.  Hash collisions
    // between genuine same-name different-type pairs are allowed —
    // equality is the source of truth, and the refined `==` will
    // correctly reject them.
    hasher.combine(structuralPath)
    hasher.combine(typeIdentity)
    hasher.combine(explicitID)
  }

  private static func explicitID(
    from identity: Identity
  ) -> String? {
    guard let lastComponent = identity.lastComponent else {
      return nil
    }
    guard lastComponent.hasPrefix("ID[") else {
      return nil
    }
    return lastComponent
  }
}
