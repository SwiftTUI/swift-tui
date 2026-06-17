extension ResolvedNode {
  package func isEquivalentForMeasurement(
    to other: Self
  ) -> Bool {
    structuralPath == other.structuralPath
      && kind == other.kind
      && Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator)
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForMeasurement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && layoutDependentContent?.equivalenceSignature
        == other.layoutDependentContent?.equivalenceSignature
      && drawPayload.isEquivalentForMeasurement(to: other.drawPayload)
      && intrinsicSize == other.intrinsicSize
      && indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature
      && children.count == other.children.count
      && zip(children, other.children).allSatisfy { lhsChild, rhsChild in
        lhsChild.isEquivalentForMeasurement(to: rhsChild)
      }
  }

  /// Stricter equivalence check used by the retained layout placement cache.
  /// Like `isEquivalentForMeasurement` but uses full draw payload equality
  /// instead of the relaxed measurement comparison, ensuring that visual-only
  /// changes (such as a shape's stroke style changing from thick to thin) are
  /// detected even when they don't affect measurement.
  package func isEquivalentForPlacement(
    to other: Self
  ) -> Bool {
    structuralPath == other.structuralPath
      && kind == other.kind
      && Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator)
      && environmentSnapshot == other.environmentSnapshot
      && layoutBehavior.isEquivalentForPlacement(to: other.layoutBehavior)
      && layoutMetadata == other.layoutMetadata
      && layoutDependentContent?.equivalenceSignature
        == other.layoutDependentContent?.equivalenceSignature
      && drawPayload == other.drawPayload
      && intrinsicSize == other.intrinsicSize
      && indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature
      && children.count == other.children.count
      && zip(children, other.children).allSatisfy { lhsChild, rhsChild in
        lhsChild.isEquivalentForPlacement(to: rhsChild)
      }
  }

  /// Result of `placementEquivalence(to:)` — how a current resolved subtree
  /// relates to a cached one for retained-placement reuse.
  package enum PlacementEquivalence {
    /// Geometry diverges — the cached placement cannot be reused.
    case divergent
    /// Placement-equivalent (cached bounds reusable) but some geometry-stable
    /// metadata mirror (color, semantics, lifecycle, animation tick…) changed,
    /// so the reused subtree must be re-synced from the current resolved tree.
    case geometryReusable
    /// Fully identical across the subtree, including every metadata field that
    /// `PlacedNode` mirrors — the cached placed subtree is already correct and
    /// can be reused untouched (no metadata sync needed).
    case identical
  }

  /// Single-walk equivalence used by the retained-placement cache. It subsumes
  /// `isEquivalentForPlacement` (the geometry gate) and additionally reports
  /// whether the geometry-stable metadata mirrors are *also* unchanged, so the
  /// caller can skip the O(subtree) `synchronizeRetainedPhaseMetadata` rebuild
  /// on the common case where resolve carried the subtree forward
  /// byte-identically. Crucially it compares fields in place — it never projects
  /// a `PlacedNodeResolvedMetadata` per node — so the metadata check adds only a
  /// handful of comparisons to a walk that already runs.
  package func placementEquivalence(
    to other: Self
  ) -> PlacementEquivalence {
    guard
      structuralPath == other.structuralPath,
      kind == other.kind,
      Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator),
      environmentSnapshot == other.environmentSnapshot,
      layoutBehavior.isEquivalentForPlacement(to: other.layoutBehavior),
      layoutMetadata == other.layoutMetadata,
      layoutDependentContent?.equivalenceSignature
        == other.layoutDependentContent?.equivalenceSignature,
      drawPayload == other.drawPayload,
      intrinsicSize == other.intrinsicSize,
      indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature,
      children.count == other.children.count
    else {
      return .divergent
    }

    // Metadata mirrored by `PlacedNode` beyond the geometry gate above. `kind`,
    // `environmentSnapshot`, `layoutMetadata`, and `drawPayload` are already
    // proven equal by the gate; `semanticRole` derives purely from
    // `semanticMetadata` / focus / `layoutBehavior`, all compared here.
    var metadataIdentical =
      identity == other.identity
      && structuralEdgeRole == other.structuralEdgeRole
      && entityIdentity == other.entityIdentity
      && entityStructuralPath == other.entityStructuralPath
      && declarationOwnerEdge == other.declarationOwnerEdge
      && layoutBehavior == other.layoutBehavior
      && drawMetadata == other.drawMetadata
      && drawEffects == other.drawEffects
      && surfaceComposition == other.surfaceComposition
      && semanticMetadata == other.semanticMetadata
      && lifecycleMetadata == other.lifecycleMetadata
      && isTransient == other.isTransient
      && matchedGeometry == other.matchedGeometry

    for (lhsChild, rhsChild) in zip(children, other.children) {
      switch lhsChild.placementEquivalence(to: rhsChild) {
      case .divergent:
        return .divergent
      case .geometryReusable:
        metadataIdentical = false
      case .identical:
        break
      }
    }

    return metadataIdentical ? .identical : .geometryReusable
  }

  /// Two discriminators are "compatible" for equivalence purposes when
  /// either both match or at least one is `nil`.  This is the bridging
  /// rule that lets migrated and un-migrated call sites coexist — a
  /// typed descriptor still matches a legacy descriptor with the same
  /// name, so partial migrations don't cause structural churn.
  package static func typeDiscriminatorsCompatible(
    _ lhs: ObjectIdentifier?,
    _ rhs: ObjectIdentifier?
  ) -> Bool {
    switch (lhs, rhs) {
    case (let l?, let r?):
      return l == r
    default:
      return true
    }
  }
}

extension ResolvedNode {
  #if DEBUG
    /// Stage-1 memo oracle: whether reusing `self` in place of `other` would be
    /// observably identical *under the semantics the real retained-reuse path
    /// guarantees* — i.e. ignoring `structuralPath` (re-stamped on reuse, see
    /// ViewFoundation reuse return) and comparing `transactionSnapshot` by
    /// `isReuseEquivalent` (the gate's check) rather than strict `==`. Every
    /// other field must match exactly, recursing into children. This is the
    /// sound oracle for memoization, vs the stricter `==` used elsewhere.
    package func memoReuseEquivalent(to other: ResolvedNode) -> Bool {
      guard
        identity == other.identity,
        structuralEdgeRole == other.structuralEdgeRole,
        entityIdentity == other.entityIdentity,
        entityStructuralPath == other.entityStructuralPath,
        declarationOwnerEdge == other.declarationOwnerEdge,
        kind == other.kind,
        Self.typeDiscriminatorsCompatible(typeDiscriminator, other.typeDiscriminator),
        environmentSnapshot == other.environmentSnapshot,
        transactionSnapshot.isReuseEquivalent(to: other.transactionSnapshot),
        layoutBehavior == other.layoutBehavior,
        layoutMetadata == other.layoutMetadata,
        layoutDependentContent?.equivalenceSignature
          == other.layoutDependentContent?.equivalenceSignature,
        drawMetadata == other.drawMetadata,
        drawEffects == other.drawEffects,
        surfaceComposition == other.surfaceComposition,
        semanticMetadata == other.semanticMetadata,
        lifecycleMetadata == other.lifecycleMetadata,
        drawPayload == other.drawPayload,
        intrinsicSize == other.intrinsicSize,
        indexedChildSource?.measurementSignature == other.indexedChildSource?.measurementSignature,
        preferenceValues == other.preferenceValues,
        supportsRetainedReuse == other.supportsRetainedReuse,
        children.count == other.children.count
      else { return false }
      for (l, r) in zip(children, other.children) where !l.memoReuseEquivalent(to: r) {
        return false
      }
      return true
    }

    /// Stage-1 memo diagnostics: returns the first field that differs under
    /// `==` (or nil if equal), to characterize the `no_reads` unsound class —
    /// whether the mismatch is real content (`drawPayload`/`kind`/`children`/…,
    /// a comparator false-equal) or per-resolve identity bookkeeping
    /// (`entityIdentity`/`structuralPath`/…, an over-strict oracle field).
    package func memoFirstDifferingField(from other: ResolvedNode) -> String? {
      if identity != other.identity { return "identity" }
      if structuralPath != other.structuralPath { return "structuralPath" }
      if structuralEdgeRole != other.structuralEdgeRole { return "structuralEdgeRole" }
      if entityIdentity != other.entityIdentity { return "entityIdentity" }
      if entityStructuralPath != other.entityStructuralPath { return "entityStructuralPath" }
      if declarationOwnerEdge != other.declarationOwnerEdge { return "declarationOwnerEdge" }
      if kind != other.kind { return "kind" }
      if children.count != other.children.count { return "children.count" }
      for (l, r) in zip(children, other.children) {
        if let childField = l.memoFirstDifferingField(from: r) {
          return "child.\(childField)"
        }
      }
      if environmentSnapshot != other.environmentSnapshot { return "environmentSnapshot" }
      if transactionSnapshot != other.transactionSnapshot { return "transactionSnapshot" }
      if layoutBehavior != other.layoutBehavior { return "layoutBehavior" }
      if layoutMetadata != other.layoutMetadata { return "layoutMetadata" }
      if drawMetadata != other.drawMetadata { return "drawMetadata" }
      if drawEffects != other.drawEffects { return "drawEffects" }
      if surfaceComposition != other.surfaceComposition { return "surfaceComposition" }
      if semanticMetadata != other.semanticMetadata { return "semanticMetadata" }
      if lifecycleMetadata != other.lifecycleMetadata { return "lifecycleMetadata" }
      if drawPayload != other.drawPayload { return "drawPayload" }
      if intrinsicSize != other.intrinsicSize { return "intrinsicSize" }
      if preferenceValues != other.preferenceValues { return "preferenceValues" }
      if supportsRetainedReuse != other.supportsRetainedReuse { return "supportsRetainedReuse" }
      return self == other ? nil : "other"
    }
  #endif

  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.identity == rhs.identity
      && lhs.structuralPath == rhs.structuralPath
      && lhs.structuralEdgeRole == rhs.structuralEdgeRole
      && lhs.entityIdentity == rhs.entityIdentity
      && lhs.entityStructuralPath == rhs.entityStructuralPath
      && lhs.declarationOwnerEdge == rhs.declarationOwnerEdge
      && lhs.kind == rhs.kind
      && Self.typeDiscriminatorsCompatible(lhs.typeDiscriminator, rhs.typeDiscriminator)
      && lhs.children == rhs.children
      && lhs.environmentSnapshot == rhs.environmentSnapshot
      && lhs.transactionSnapshot == rhs.transactionSnapshot
      && lhs.layoutBehavior == rhs.layoutBehavior
      && lhs.layoutMetadata == rhs.layoutMetadata
      && lhs.layoutDependentContent?.equivalenceSignature
        == rhs.layoutDependentContent?.equivalenceSignature
      && lhs.drawMetadata == rhs.drawMetadata
      && lhs.drawEffects == rhs.drawEffects
      && lhs.surfaceComposition == rhs.surfaceComposition
      && lhs.semanticMetadata == rhs.semanticMetadata
      && lhs.lifecycleMetadata == rhs.lifecycleMetadata
      && lhs.drawPayload == rhs.drawPayload
      && lhs.intrinsicSize == rhs.intrinsicSize
      && lhs.indexedChildSource?.measurementSignature
        == rhs.indexedChildSource?.measurementSignature
      && lhs.preferenceValues == rhs.preferenceValues
      && lhs.supportsRetainedReuse == rhs.supportsRetainedReuse
  }
}
