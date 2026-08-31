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
  // Internal (not fileprivate) so the shape-stable patcher in
  // `RetainedFrameIndexPatching.swift` can carry these tables forward; the
  // package-facing surface stays the accessor methods below.
  let resolvedStructuralIndex: [Identity: ResolvedNode]
  let measuredStructuralIndex: [Identity: MeasuredNode]
  let placedStructuralIndex: [Identity: PlacedNode]
  /// The frame's placed tree. `PlacedNode` carries its whole subtree, so this
  /// is the previous frame's placed root and, transitively, every placed node.
  /// Held for ``placedRootIdentity`` — where ``placedPath(to:)`` terminates —
  /// and for byte-equivalence; the incremental-damage producer diffs the
  /// retained *draw* trees, not this tree. Holding it costs nothing beyond the
  /// reference the index's structural map already retains.
  package let placedRoot: PlacedNode
  /// The identity of the frame's placed root — the node ``placedPath(to:)``
  /// terminates at.
  package var placedRootIdentity: Identity {
    placedRoot.identity
  }
  /// Real parent edges of the placed tree, child identity → placed parent
  /// identity.
  ///
  /// Ancestry is recorded during the indexing walk rather than derived from
  /// `StructuralPath.parent`, which is purely lexical: it drops the last path
  /// component and terminates only at the empty identity. A lexical climb
  /// walks off the top of the placed tree (a real app roots its placed tree at
  /// the window content, so the app/scene identities above it never own a
  /// `PlacedNode`) and also breaks whenever a placed child's identity extends
  /// its placed parent's by more than one component.
  let placedParentByStructuralIdentity: [Identity: Identity]
  let placedFrameEntries: [PlacedFrameTableEntry]
  let placedFrameEntryRangesByNodeID: [ViewNodeID: Range<Int>]
  let placedFrameEntryRangesByStructuralIdentity: [Identity: Range<Int>]
  /// Whether this index was derived by the shape-stable incremental patch
  /// rather than a full rebuild. Diagnostic provenance only — deliberately
  /// excluded from ``isByteEquivalent(to:)``, whose contract is that a
  /// patched index and a full rebuild are indistinguishable by content.
  package let derivedByPatching: Bool

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
    var placedParentByStructuralIdentity: [Identity: Identity] = [:]
    var placedFrameEntries: [PlacedFrameTableEntry] = []
    var placedFrameEntryRangesByNodeID: [ViewNodeID: Range<Int>] = [:]
    var placedFrameEntryRangesByStructuralIdentity: [Identity: Range<Int>] = [:]
    Self.index(
      frame.placedTree,
      parent: nil,
      into: &placedByNodeID,
      structuralIndex: &placedStructuralIndex,
      parentStructuralIndex: &placedParentByStructuralIdentity,
      placedFrameEntries: &placedFrameEntries,
      placedFrameEntryRangesByNodeID: &placedFrameEntryRangesByNodeID,
      placedFrameEntryRangesByStructuralIdentity: &placedFrameEntryRangesByStructuralIdentity
    )
    self.placedByNodeID = placedByNodeID
    self.placedStructuralIndex = placedStructuralIndex
    self.placedRoot = frame.placedTree
    self.placedParentByStructuralIdentity = placedParentByStructuralIdentity
    self.placedFrameEntries = placedFrameEntries
    self.placedFrameEntryRangesByNodeID = placedFrameEntryRangesByNodeID
    self.placedFrameEntryRangesByStructuralIdentity =
      placedFrameEntryRangesByStructuralIdentity
    derivedByPatching = false
  }

  /// Memberwise assembly for the shape-stable patcher
  /// (`RetainedFrameIndexPatching.swift`); every other caller goes through
  /// `init(frame:)` or `init(patching:with:)`.
  init(
    resolvedByNodeID: [ViewNodeID: ResolvedNode],
    measuredByNodeID: [ViewNodeID: MeasuredNode],
    placedByNodeID: [ViewNodeID: PlacedNode],
    structuralFrame: StructuralFrameIndex,
    resolvedStructuralIndex: [Identity: ResolvedNode],
    measuredStructuralIndex: [Identity: MeasuredNode],
    placedStructuralIndex: [Identity: PlacedNode],
    placedRoot: PlacedNode,
    placedParentByStructuralIdentity: [Identity: Identity],
    placedFrameEntries: [PlacedFrameTableEntry],
    placedFrameEntryRangesByNodeID: [ViewNodeID: Range<Int>],
    placedFrameEntryRangesByStructuralIdentity: [Identity: Range<Int>],
    derivedByPatching: Bool
  ) {
    self.resolvedByNodeID = resolvedByNodeID
    self.measuredByNodeID = measuredByNodeID
    self.placedByNodeID = placedByNodeID
    self.structuralFrame = structuralFrame
    self.resolvedStructuralIndex = resolvedStructuralIndex
    self.measuredStructuralIndex = measuredStructuralIndex
    self.placedStructuralIndex = placedStructuralIndex
    self.placedRoot = placedRoot
    self.placedParentByStructuralIdentity = placedParentByStructuralIdentity
    self.placedFrameEntries = placedFrameEntries
    self.placedFrameEntryRangesByNodeID = placedFrameEntryRangesByNodeID
    self.placedFrameEntryRangesByStructuralIdentity =
      placedFrameEntryRangesByStructuralIdentity
    self.derivedByPatching = derivedByPatching
  }

  /// Derives the next retained index from the previous one plus the new frame.
  ///
  /// Frames whose trees keep the previous frame's shape — every identity,
  /// kind, structural path, and child count pairwise unchanged, the dominant
  /// value-only class (state flips, animation ticks) — patch incrementally:
  /// the structural tables carry over wholesale (walk-order key minting is a
  /// pure function of the resolved tree's shape) and only changed nodes'
  /// phase entries are rewritten, with descent pruned wherever a paired
  /// subtree compares equal. Structural changes fall back to a full rebuild
  /// by design: `StructuralNodeKey`s are minted in per-frame walk order, so
  /// a shape change renumbers the key space and the rebuild *is* the patch.
  /// Duplicate runtime identities also force the rebuild arm — positional
  /// pairing is only sound when identities are unique (the reverted
  /// paired-walk defect class; see proposal 2026-07-14-003 §Slice B).
  ///
  /// In DEBUG a patched index is checked byte-equivalent against a full
  /// rebuild — the oracle this initializer carried, inert, until the patch
  /// path landed.
  ///
  /// `verifyingAgainstFullRebuild` is that oracle's sampling gate. It used to
  /// have none: a raw `#if DEBUG`, so every shape-stable frame in every debug
  /// build paid for the full rebuild this patch path exists to avoid, plus a
  /// field-by-field comparison of both indexes. That is the only oracle in the
  /// system that consulted no probe, and it is invisible in a consumer's test
  /// suite. The frame tail passes
  /// ``SoundnessProbeConfiguration/isSampledFrame`` down from the main actor —
  /// the same hop `Rasterizer.rasterizeCollectingVisibleIdentities`'s
  /// `verifyIncrementalRasterDamage` already makes, because this type is built
  /// on the frame-tail worker and the probe is main-actor state. Direct
  /// callers (tests) keep the oracle on by default.
  package init(
    patching previous: RetainedFrameIndex?,
    with frame: FrameArtifacts,
    verifyingAgainstFullRebuild: Bool = true
  ) {
    if let previous,
      let patched = RetainedFrameIndex(patchingShapeStable: previous, frame: frame)
    {
      self = patched
      #if DEBUG
        if verifyingAgainstFullRebuild {
          let rebuilt = RetainedFrameIndex(frame: frame)
          if let divergence = byteDivergenceDescription(from: rebuilt) {
            preconditionFailure(
              "RetainedFrameIndex patch diverged from full rebuild: \(divergence)"
            )
          }
        }
      #endif
    } else {
      self.init(frame: frame)
    }
  }

  /// The first field on which this index differs from `other`, or `nil` when
  /// byte-equivalent — the DEBUG patch oracle's failure diagnostic.
  package func byteDivergenceDescription(
    from other: RetainedFrameIndex
  ) -> String? {
    if resolvedByNodeID != other.resolvedByNodeID { return "resolvedByNodeID" }
    if measuredByNodeID != other.measuredByNodeID { return "measuredByNodeID" }
    if placedByNodeID != other.placedByNodeID { return "placedByNodeID" }
    if structuralFrame != other.structuralFrame { return "structuralFrame" }
    if resolvedStructuralIndex != other.resolvedStructuralIndex {
      return "resolvedStructuralIndex"
    }
    if measuredStructuralIndex != other.measuredStructuralIndex {
      return "measuredStructuralIndex"
    }
    if placedStructuralIndex != other.placedStructuralIndex { return "placedStructuralIndex" }
    if placedRoot != other.placedRoot { return "placedRoot" }
    if placedParentByStructuralIdentity != other.placedParentByStructuralIdentity {
      return "placedParentByStructuralIdentity"
    }
    if placedFrameEntries != other.placedFrameEntries { return "placedFrameEntries" }
    if placedFrameEntryRangesByNodeID != other.placedFrameEntryRangesByNodeID {
      return "placedFrameEntryRangesByNodeID"
    }
    if placedFrameEntryRangesByStructuralIdentity
      != other.placedFrameEntryRangesByStructuralIdentity
    {
      return "placedFrameEntryRangesByStructuralIdentity"
    }
    return nil
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
      && placedRoot == other.placedRoot
      && placedParentByStructuralIdentity == other.placedParentByStructuralIdentity
      && placedFrameEntries == other.placedFrameEntries
      && placedFrameEntryRangesByNodeID == other.placedFrameEntryRangesByNodeID
      && placedFrameEntryRangesByStructuralIdentity
        == other.placedFrameEntryRangesByStructuralIdentity
  }

  /// Runtime identities that resolved to more than one structural node this
  /// frame — duplicate explicit ids (a non-unique `ForEach` id keypath or a
  /// reused `.id(_:)`), which since the occurrence-aware node store get distinct
  /// `ViewNodeID` lifetimes that nonetheless share one `Identity`.
  ///
  /// The flat identity-keyed accessors below (`resolvedNode(for:)`,
  /// `measuredNode(for:)`, `placedNode(for:)`) collapse such collisions
  /// last-writer-wins; the per-`ViewNodeID` tables (`resolvedByNodeID`, …) and
  /// the multimap `structuralFrame` retain every sibling. Surfacing the
  /// collisions here makes the collapse queryable from the commit path instead
  /// of silent (G12); the resolve pass additionally emits a deterministic
  /// `identity.duplicateEntity` `RuntimeIssue` per frame. Order is stable for a
  /// fixed tree (it follows the deterministic structural walk).
  package var duplicateRuntimeIdentities: [Identity] {
    structuralFrame.nodeByRuntimeIdentity
      .compactMap { identity, keys in keys.count > 1 ? identity : nil }
  }

  /// Returns the previous frame's resolved node for `identity`.
  ///
  /// Last-writer-wins for duplicate explicit ids — see
  /// ``duplicateRuntimeIdentities``; use ``resolvedByNodeID`` keyed on the
  /// unambiguous `ViewNodeID` when a specific duplicate sibling is required.
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

  /// Climbs recorded placed-tree edges from `identity` up to the placed root.
  ///
  /// Returns `nil` when the identity is not placed or any hop is missing, so
  /// the damage resolver stays conservative for genuinely unplaced subtrees.
  package func placedPath(
    to identity: Identity
  ) -> [PlacedNode]? {
    var reversedPath: [PlacedNode] = []
    var current = identity

    while true {
      guard let node = placedStructuralIndex[current] else {
        return nil
      }
      reversedPath.append(node)
      if current == placedRootIdentity {
        break
      }
      guard let parent = placedParentByStructuralIdentity[current] else {
        return nil
      }
      // Duplicate explicit ids collapse last-writer-wins, which can in
      // principle point an identity at one of its own descendants. Bounding by
      // the node count keeps the climb terminating; ``duplicateRuntimeIdentities``
      // is what lets the damage resolver reject such a frame outright.
      guard reversedPath.count <= placedStructuralIndex.count else {
        return nil
      }
      current = parent
    }

    return reversedPath.reversed()
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
    parent: Identity?,
    into storage: inout [ViewNodeID: PlacedNode],
    structuralIndex: inout [Identity: PlacedNode],
    parentStructuralIndex: inout [Identity: Identity],
    placedFrameEntries: inout [PlacedFrameTableEntry],
    placedFrameEntryRangesByNodeID: inout [ViewNodeID: Range<Int>],
    placedFrameEntryRangesByStructuralIdentity: inout [Identity: Range<Int>]
  ) {
    let start = placedFrameEntries.count
    if let viewNodeID = node.viewNodeID {
      storage[viewNodeID] = node
    }
    structuralIndex[node.identity] = node
    if let parent {
      parentStructuralIndex[node.identity] = parent
    }
    placedFrameEntries.append(
      .init(
        viewNodeID: node.viewNodeID,
        identity: node.identity,
        bounds: node.bounds,
        namedCoordinateSpace: node.semanticMetadata.namedCoordinateSpace
      )
    )
    for child in node.children {
      index(
        child,
        parent: node.identity,
        into: &storage,
        structuralIndex: &structuralIndex,
        parentStructuralIndex: &parentStructuralIndex,
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
  /// Frame-constant resolution of `directlyInvalidated` to structural node
  /// keys, computed once so the per-candidate `intersectsSubtree` queries
  /// (measure/place reuse gates, phase-reuse collection) never rebuild it.
  private let invalidatedNodeKeys: Set<StructuralNodeKey>
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
      invalidatedNodeKeys = []
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
    let invalidatedNodeKeys = previousStructuralFrame.nodeKeys(for: invalidatedIdentities)
    self.invalidatedNodeKeys = invalidatedNodeKeys

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
          invalidatedNodes: invalidatedNodeKeys,
          invalidatedIdentities: invalidatedIdentities
        )
        if structuralResult == true
          || ((structuralResult == nil || hasUnindexedInvalidations)
            && base.intersectsSubtree(at: source.identityRoot))
        {
          affectedIndexedChildSourceRoots.insert(source.identityRoot)
          continue
        }
        // An invalidated ANCESTOR means the container's body may have re-run
        // with new per-ID payloads. The indexed measurement signature is the
        // ordered ID list — payload changes under a stable ID list are
        // invisible to every equivalence comparator for indexed containers —
        // so the source must yield reuse whenever an ancestor re-resolved.
        var ancestor: StructuralPath? = StructuralPath(identity: source.identityRoot)
        while let current = ancestor {
          if invalidatedIdentities.contains(current.identityProjection) {
            affectedIndexedChildSourceRoots.insert(source.identityRoot)
            break
          }
          ancestor = current.parent
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
      invalidatedNodes: invalidatedNodeKeys
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

  /// Whether any affected indexed source lives at or inside `identity`'s
  /// subtree. Ancestor reuse gates need the subtree form: retained
  /// measurement can reuse a whole enclosing subtree (ScrollView, frame)
  /// whose comparator is signature-blind inside the indexed container, so
  /// the container's own gate never runs unless every ancestor asks this.
  package func affectsIndexedChildSource(
    within identity: Identity
  ) -> Bool {
    !affectedIndexedChildSourceRoots.isEmpty
      && affectedIndexedChildSourceRoots.contains {
        $0 == identity || $0.isDescendant(of: identity)
      }
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    if let structuralResult = structuralFrame?.intersectsSubtree(
      at: identity,
      invalidatedNodes: invalidatedNodeKeys,
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

  package func affectsIndexedChildSource(
    within identity: Identity
  ) -> Bool {
    invalidationSummary.affectsIndexedChildSource(within: identity)
  }
}
