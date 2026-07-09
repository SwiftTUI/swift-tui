package struct ChildDescriptor: Hashable, Sendable {
  package var identity: Identity
  package var structuralPath: StructuralPath
  package var entityIdentity: EntityIdentity?
  package var entityStructuralPath: StructuralPath?
  package var typeIdentity: String
  /// Refines the String `typeIdentity` with a stable per-Swift-type
  /// discriminator when one is available.  Two descriptors with the same
  /// `typeIdentity` but different non-nil discriminators are unequal:
  /// this catches accidental kind-name collisions that a String-only
  /// comparison would silently fuse.  When either side is `nil` (legacy
  /// call site or in-progress migration) the comparison falls back to
  /// the String, so partial migrations don't produce structural churn.
  package var typeDiscriminator: ObjectIdentifier?

  package init(
    identity: Identity,
    structuralPath: StructuralPath? = nil,
    entityIdentity: EntityIdentity? = nil,
    entityStructuralPath: StructuralPath? = nil,
    typeIdentity: String,
    typeDiscriminator: ObjectIdentifier? = nil
  ) {
    self.identity = identity
    self.structuralPath = structuralPath ?? StructuralPath(identity: identity)
    self.entityIdentity = entityIdentity
    self.entityStructuralPath = entityStructuralPath
    self.typeIdentity = typeIdentity
    self.typeDiscriminator = typeDiscriminator
  }

  package init(resolvedNode: ResolvedNode) {
    identity = resolvedNode.identity
    structuralPath = resolvedNode.structuralPath
    entityIdentity = resolvedNode.entityIdentity
    entityStructuralPath = resolvedNode.entityStructuralPath
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
  }

  package static func == (lhs: Self, rhs: Self) -> Bool {
    guard lhs.reconciliationStructuralPath == rhs.reconciliationStructuralPath,
      lhs.entityIdentity == rhs.entityIdentity,
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
    hasher.combine(reconciliationStructuralPath)
    hasher.combine(typeIdentity)
    hasher.combine(entityIdentity)
  }

  private var reconciliationStructuralPath: StructuralPath {
    guard entityIdentity != nil,
      let entityStructuralPath,
      entityStructuralPath.isAncestor(of: structuralPath)
    else {
      return structuralPath
    }

    let prefix = entityStructuralPath.parent?.components ?? []
    let suffix = structuralPath.components.dropFirst(entityStructuralPath.components.count)
    return StructuralPath(components: prefix + suffix)
  }
}

extension ResolvedNode {
  package func duplicateEntityIdentityRuntimeIssues() -> [RuntimeIssue] {
    var issues: [RuntimeIssue] = []
    var reported: Set<DuplicateEntityIdentityIssueKey> = []

    func visit(_ node: ResolvedNode) {
      if let entityIdentity = node.entityIdentity,
        entityIdentity.occurrence > 0
      {
        let sourcePath = node.entityStructuralPath ?? node.structuralPath
        let key = DuplicateEntityIdentityIssueKey(
          value: entityIdentity.value,
          occurrence: entityIdentity.occurrence,
          sourcePath: sourcePath
        )

        if reported.insert(key).inserted {
          issues.append(
            RuntimeIssue(
              severity: .warning,
              code: "identity.duplicateEntity",
              message:
                "Duplicate entity id \(entityIdentity.debugDescription) resolved at occurrence \(entityIdentity.occurrence) for \(node.kind) in structural slot \(sourcePath.description); lifetime matching is deterministic but duplicate ids are undefined user input.",
              identity: node.identity,
              source: "EntityIdentity"
            )
          )
        }
      }

      for child in node.children {
        visit(child)
      }
    }

    visit(self)
    return issues
  }
}

private struct DuplicateEntityIdentityIssueKey: Hashable {
  var value: AnyID
  var occurrence: Int
  var sourcePath: StructuralPath
}
