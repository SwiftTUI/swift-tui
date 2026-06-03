// Read-only query surface over the previous committed frame.
//
// Incremental layout reuses the last frame's pipeline products instead of
// recomputing untouched subtrees. Three value types make that retained state
// queryable, from raw to refined:
//
//  - `RetainedFrameIndex` — flat `ViewNodeID` → node lookup tables built once per
//    committed frame.
//  - `RetainedInvalidationSummary` — classifies this frame's invalidations
//    against the previous index (synthetic ancestors, affected indexed child
//    sources, subtree intersection).
//  - `RetainedLayoutSession` — pairs an index with a summary and re-derives the
//    summary whenever `invalidatedIdentities` changes; this is what the layout
//    engine actually consults.
//
// All three are `Sendable` and side-effect free. They previously lived in
// `RetainedResolveFrame.swift` alongside the mutable `LayoutPassContext`.

/// Runtime-lifetime index of the previous committed frame's canonical pipeline products.
///
/// When this index is produced by frame-tail retained state, `placedByNodeID`
/// is expected to come from the baseline placed tree stored before animation
/// overlays were injected. That keeps retained placement keyed to canonical
/// layout, while overlays are re-applied from animation state each frame.
package struct RetainedFrameIndex: Sendable {
  package let resolvedByNodeID: [ViewNodeID: ResolvedNode]
  package let measuredByNodeID: [ViewNodeID: MeasuredNode]
  package let placedByNodeID: [ViewNodeID: PlacedNode]
  package let structuralFrame: StructuralFrameIndex
  fileprivate let resolvedStructuralIndex: [Identity: ResolvedNode]
  fileprivate let measuredStructuralIndex: [Identity: MeasuredNode]
  fileprivate let placedStructuralIndex: [Identity: PlacedNode]
  private let placedFrameEntries: [PlacedFrameTableEntry]
  private let placedFrameEntryRangesByNodeID: [ViewNodeID: Range<Int>]
  private let placedFrameEntryRangesByStructuralIdentity: [Identity: Range<Int>]

  package var placedFrameEntryCount: Int {
    placedFrameEntries.count
  }

  package init(frame: FrameArtifacts) {
    structuralFrame = StructuralFrameIndex(root: frame.resolvedTree)

    var resolvedByNodeID: [ViewNodeID: ResolvedNode] = [:]
    var resolvedStructuralIndex: [Identity: ResolvedNode] = [:]
    Self.index(
      frame.resolvedTree, into: &resolvedByNodeID, structuralIndex: &resolvedStructuralIndex)
    self.resolvedByNodeID = resolvedByNodeID
    self.resolvedStructuralIndex = resolvedStructuralIndex

    var measuredByNodeID: [ViewNodeID: MeasuredNode] = [:]
    var measuredStructuralIndex: [Identity: MeasuredNode] = [:]
    Self.index(
      frame.measuredTree, into: &measuredByNodeID, structuralIndex: &measuredStructuralIndex)
    self.measuredByNodeID = measuredByNodeID
    self.measuredStructuralIndex = measuredStructuralIndex

    var placedByNodeID: [ViewNodeID: PlacedNode] = [:]
    var placedStructuralIndex: [Identity: PlacedNode] = [:]
    var placedFrameEntries: [PlacedFrameTableEntry] = []
    var placedFrameEntryRangesByNodeID: [ViewNodeID: Range<Int>] = [:]
    var placedFrameEntryRangesByStructuralIdentity: [Identity: Range<Int>] = [:]
    Self.index(
      frame.placedTree,
      into: &placedByNodeID,
      structuralIndex: &placedStructuralIndex,
      placedFrameEntries: &placedFrameEntries,
      placedFrameEntryRangesByNodeID: &placedFrameEntryRangesByNodeID,
      placedFrameEntryRangesByStructuralIdentity: &placedFrameEntryRangesByStructuralIdentity
    )
    self.placedByNodeID = placedByNodeID
    self.placedStructuralIndex = placedStructuralIndex
    self.placedFrameEntries = placedFrameEntries
    self.placedFrameEntryRangesByNodeID = placedFrameEntryRangesByNodeID
    self.placedFrameEntryRangesByStructuralIdentity =
      placedFrameEntryRangesByStructuralIdentity
  }

  /// Derives the next retained index from the previous one plus the new frame.
  ///
  /// **The incremental fragment patch (Stage 1 L3) is deferred:** this currently
  /// performs a full rebuild (`init(frame:)`), so `previous` is unused except by
  /// the debug check below. Measurement shows retained-index construction is a
  /// sub-1% slice of frame time (off the critical path; `resolve_ms` dominates),
  /// so the incremental patcher was not worth its complexity — see
  /// `docs/VISION-GAP.md` (Structural identity). Until a real patch path lands,
  /// the `#if DEBUG` byte-equivalence check compares two full rebuilds and is
  /// therefore inert; it is retained as the oracle scaffold that becomes
  /// meaningful the moment the patched and rebuilt indexes can differ.
  package init(
    patching previous: RetainedFrameIndex?,
    with frame: FrameArtifacts
  ) {
    self.init(frame: frame)

    #if DEBUG
      // Inert until the incremental patch path exists (see doc comment): this
      // compares a full rebuild against another full rebuild.
      if previous != nil {
        let rebuilt = RetainedFrameIndex(frame: frame)
        precondition(
          isByteEquivalent(to: rebuilt),
          "RetainedFrameIndex patch diverged from full rebuild"
        )
      }
    #endif
  }

  package func isByteEquivalent(
    to other: RetainedFrameIndex
  ) -> Bool {
    resolvedByNodeID == other.resolvedByNodeID
      && measuredByNodeID == other.measuredByNodeID
      && placedByNodeID == other.placedByNodeID
      && structuralFrame == other.structuralFrame
      && resolvedStructuralIndex == other.resolvedStructuralIndex
      && measuredStructuralIndex == other.measuredStructuralIndex
      && placedStructuralIndex == other.placedStructuralIndex
      && placedFrameEntries == other.placedFrameEntries
      && placedFrameEntryRangesByNodeID == other.placedFrameEntryRangesByNodeID
      && placedFrameEntryRangesByStructuralIdentity
        == other.placedFrameEntryRangesByStructuralIdentity
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    resolvedStructuralIndex[identity]
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    measuredStructuralIndex[identity]
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    placedStructuralIndex[identity]
  }

  package func placedPath(
    to identity: Identity
  ) -> [PlacedNode]? {
    var identities: [Identity] = []
    var currentIdentity: Identity? = identity

    while let current = currentIdentity {
      guard placedStructuralIndex[current] != nil else {
        return nil
      }
      identities.append(current)
      currentIdentity = StructuralPath(identity: current).parent?.identityProjection
    }

    return identities.reversed().compactMap { placedStructuralIndex[$0] }
  }

  package func placedFrameFragment(
    for identity: Identity
  ) -> PlacedFrameTableFragment? {
    guard let range = placedFrameEntryRangesByStructuralIdentity[identity] else {
      return nil
    }
    return .init(entries: placedFrameEntries[range])
  }

  private static func index(
    _ node: ResolvedNode,
    into storage: inout [ViewNodeID: ResolvedNode],
    structuralIndex: inout [Identity: ResolvedNode]
  ) {
    if let viewNodeID = node.viewNodeID {
      storage[viewNodeID] = node
    }
    structuralIndex[node.identity] = node
    for child in node.children {
      index(child, into: &storage, structuralIndex: &structuralIndex)
    }
  }

  private static func index(
    _ node: MeasuredNode,
    into storage: inout [ViewNodeID: MeasuredNode],
    structuralIndex: inout [Identity: MeasuredNode]
  ) {
    if let viewNodeID = node.viewNodeID {
      storage[viewNodeID] = node
    }
    structuralIndex[node.identity] = node
    for child in node.childMeasurements {
      index(child, into: &storage, structuralIndex: &structuralIndex)
    }
  }

  private static func index(
    _ node: PlacedNode,
    into storage: inout [ViewNodeID: PlacedNode],
    structuralIndex: inout [Identity: PlacedNode],
    placedFrameEntries: inout [PlacedFrameTableEntry],
    placedFrameEntryRangesByNodeID: inout [ViewNodeID: Range<Int>],
    placedFrameEntryRangesByStructuralIdentity: inout [Identity: Range<Int>]
  ) {
    let start = placedFrameEntries.count
    if let viewNodeID = node.viewNodeID {
      storage[viewNodeID] = node
    }
    structuralIndex[node.identity] = node
    placedFrameEntries.append(
      .init(
        viewNodeID: node.viewNodeID,
        identity: node.identity,
        bounds: node.bounds,
        namedCoordinateSpaceName: node.semanticMetadata.namedCoordinateSpaceName
      )
    )
    for child in node.children {
      index(
        child,
        into: &storage,
        structuralIndex: &structuralIndex,
        placedFrameEntries: &placedFrameEntries,
        placedFrameEntryRangesByNodeID: &placedFrameEntryRangesByNodeID,
        placedFrameEntryRangesByStructuralIdentity: &placedFrameEntryRangesByStructuralIdentity
      )
    }
    if let viewNodeID = node.viewNodeID {
      placedFrameEntryRangesByNodeID[viewNodeID] = start..<placedFrameEntries.count
    }
    placedFrameEntryRangesByStructuralIdentity[node.identity] = start..<placedFrameEntries.count
  }
}

package struct RetainedInvalidationSummary: Sendable {
  private let base: InvalidationSummary
  private let structuralFrame: StructuralFrameIndex?
  private let hasUnindexedInvalidations: Bool
  package let identitiesWithSyntheticInvalidatedAncestors: Set<Identity>
  package let affectedIndexedChildSourceRoots: Set<Identity>

  package var directlyInvalidated: Set<Identity> {
    base.directlyInvalidated
  }

  package var identitiesWithInvalidatedDescendants: Set<Identity> {
    base.identitiesWithInvalidatedDescendants
  }

  package init(
    invalidatedIdentities: Set<Identity>,
    previousFrameIndex: RetainedFrameIndex?
  ) {
    let base = InvalidationSummary(
      invalidatedIdentities: invalidatedIdentities
    )
    self.base = base

    guard let previousFrameIndex else {
      structuralFrame = nil
      hasUnindexedInvalidations = false
      identitiesWithSyntheticInvalidatedAncestors = []
      affectedIndexedChildSourceRoots = []
      return
    }

    let previousStructuralFrame = previousFrameIndex.structuralFrame
    let hasUnindexedInvalidations = !invalidatedIdentities.isSubset(
      of: previousStructuralFrame.runtimeIdentities
    )
    structuralFrame = previousStructuralFrame
    self.hasUnindexedInvalidations = hasUnindexedInvalidations

    let previousResolvedIdentities = previousStructuralFrame.runtimeIdentities
    let syntheticInvalidatedIdentities = invalidatedIdentities.subtracting(
      previousResolvedIdentities)

    var identitiesWithSyntheticInvalidatedAncestors: Set<Identity> = []
    if !syntheticInvalidatedIdentities.isEmpty {
      for identity in previousResolvedIdentities {
        if previousStructuralFrame.hasInvalidatedAncestor(
          of: identity,
          invalidatedIdentities: syntheticInvalidatedIdentities
        ) == true {
          identitiesWithSyntheticInvalidatedAncestors.insert(identity)
          continue
        }
        var ancestor = StructuralPath(identity: identity).parent
        while let current = ancestor {
          if syntheticInvalidatedIdentities.contains(current.identityProjection) {
            identitiesWithSyntheticInvalidatedAncestors.insert(identity)
            break
          }
          ancestor = current.parent
        }
      }
    }
    self.identitiesWithSyntheticInvalidatedAncestors = identitiesWithSyntheticInvalidatedAncestors

    var affectedIndexedChildSourceRoots: Set<Identity> = []
    if !invalidatedIdentities.isEmpty {
      for resolvedNode in previousFrameIndex.resolvedStructuralIndex.values {
        guard let source = resolvedNode.indexedChildSource else {
          continue
        }
        let structuralResult = previousStructuralFrame.intersectsSubtree(
          at: source.identityRoot,
          invalidatedIdentities: invalidatedIdentities
        )
        if structuralResult == true
          || ((structuralResult == nil || hasUnindexedInvalidations)
            && base.intersectsSubtree(at: source.identityRoot))
        {
          affectedIndexedChildSourceRoots.insert(source.identityRoot)
        }
      }
    }
    self.affectedIndexedChildSourceRoots = affectedIndexedChildSourceRoots
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    base.isDirectlyInvalidated(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    if let structuralResult = structuralFrame?.containsInvalidatedDescendant(
      of: identity,
      invalidatedIdentities: directlyInvalidated
    ) {
      if structuralResult || !hasUnindexedInvalidations {
        return structuralResult
      }
    }
    return base.containsInvalidatedDescendant(of: identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    identitiesWithSyntheticInvalidatedAncestors.contains(identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    affectedIndexedChildSourceRoots.contains(identityRoot)
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    if let structuralResult = structuralFrame?.intersectsSubtree(
      at: identity,
      invalidatedIdentities: directlyInvalidated
    ) {
      if structuralResult || !hasUnindexedInvalidations {
        return structuralResult
      }
    }
    return base.intersectsSubtree(at: identity)
  }
}

package struct RetainedLayoutSession: Sendable {
  package var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities,
        previousFrameIndex: previousFrameIndex
      )
    }
  }
  package let previousFrameIndex: RetainedFrameIndex?
  package var invalidationSummary: RetainedInvalidationSummary

  package init(
    previousFrameIndex: RetainedFrameIndex?,
    invalidatedIdentities: Set<Identity>
  ) {
    self.invalidatedIdentities = invalidatedIdentities
    self.previousFrameIndex = previousFrameIndex
    invalidationSummary = RetainedInvalidationSummary(
      invalidatedIdentities: invalidatedIdentities,
      previousFrameIndex: previousFrameIndex
    )
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    previousFrameIndex?.resolvedNode(for: identity)
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    previousFrameIndex?.measuredNode(for: identity)
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    previousFrameIndex?.placedNode(for: identity)
  }

  package func placedFrameFragment(
    for identity: Identity
  ) -> PlacedFrameTableFragment? {
    previousFrameIndex?.placedFrameFragment(for: identity)
  }

  package func invalidationAffectsSubtree(
    at identity: Identity
  ) -> Bool {
    invalidationSummary.intersectsSubtree(at: identity)
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.isDirectlyInvalidated(identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.hasSyntheticInvalidatedAncestor(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    invalidationSummary.containsInvalidatedDescendant(of: identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    invalidationSummary.affectsIndexedChildSource(root: identityRoot)
  }
}
