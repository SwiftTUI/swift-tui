// Shape-stable incremental patching for `RetainedFrameIndex`.
//
// `StructuralNodeKey`s are minted in deterministic per-frame walk order, so a
// frame whose resolved tree keeps the previous frame's shape — every identity,
// kind, structural path, and child count pairwise unchanged — rebuilds to an
// index whose structural tables are byte-identical to the previous frame's.
// That is the patch window: carry the structural frame, parent map, and both
// identity-keyed range tables forward untouched, pair the new trees against
// the previous ones positionally, prune descent wherever a paired subtree
// compares equal, and rewrite only the changed nodes' identity-keyed entries
// plus their flat placed-entry slots.
//
// Two table families deliberately do NOT patch surgically:
//
//  - The four `ViewNodeID`-keyed tables rebuild wholesale each patch, via
//    walks that mirror `init(frame:)`'s write orders exactly. A `ViewNodeID`
//    is not unique within a frame — transparent chain absorption stamps a
//    wrapper's absorbed levels with the absorber's id — and the full rebuild
//    collapses those collisions with two different winners (storage tables
//    write preorder, the placed range table writes postorder), so a surgical
//    rekey cannot reproduce the collapse from local information. The walks
//    are cheap relative to what patching skips: `UInt64` keys, no identity
//    hashing, and none of the structural index's per-node signature work.
//
//  - Pairing is positional, never through the identity-keyed tables: those
//    collapse duplicate runtime identities last-writer-wins, which is exactly
//    how the reverted paired-walk equivalence proof selected the wrong hosted
//    occurrence (proposal 2026-07-14-003 §Slice B). Frames whose previous
//    index contains any duplicate identity take the rebuild arm outright.
//
// Any pairing mismatch aborts to a full rebuild — a shape change renumbers
// the walk-order key space, so the rebuild *is* the patch for structural
// frames — and the `#if DEBUG` oracle in `init(patching:with:)` checks every
// patched frame byte-equivalent against a fresh rebuild.

extension RetainedFrameIndex {
  /// Attempts the shape-stable patch; returns `nil` when the frame must take
  /// the full-rebuild arm (structural change, duplicate identities, or a
  /// previous index this frame's roots cannot be paired against).
  init?(
    patchingShapeStable previous: RetainedFrameIndex,
    frame: FrameArtifacts
  ) {
    // Positional pairing is only sound when runtime identities are unique.
    // One node per identity makes the multimap count equal the node count.
    guard
      previous.structuralFrame.nodeByRuntimeIdentity.count
        == previous.structuralFrame.postorder.count
    else {
      return nil
    }

    guard
      let previousRootKey = previous.structuralFrame.root,
      let previousResolvedRootIdentity =
        previous.structuralFrame.runtimeIdentityByNode[previousRootKey],
      previousResolvedRootIdentity == frame.resolvedTree.identity,
      let previousResolvedRoot =
        previous.resolvedStructuralIndex[previousResolvedRootIdentity],
      let previousMeasuredRoot =
        previous.measuredStructuralIndex[frame.measuredTree.identity],
      previous.placedRoot.identity == frame.placedTree.identity,
      previous.placedFrameEntries.count == frame.placedTree.subtreeNodeCount
    else {
      return nil
    }

    var resolvedStructuralIndex = previous.resolvedStructuralIndex
    guard
      Self.patchResolvedIdentityTable(
        new: frame.resolvedTree,
        previous: previousResolvedRoot,
        byIdentity: &resolvedStructuralIndex
      )
    else {
      return nil
    }

    var measuredStructuralIndex = previous.measuredStructuralIndex
    guard
      Self.patchMeasuredIdentityTable(
        new: frame.measuredTree,
        previous: previousMeasuredRoot,
        byIdentity: &measuredStructuralIndex
      )
    else {
      return nil
    }

    var placedStructuralIndex = previous.placedStructuralIndex
    var placedFrameEntries = previous.placedFrameEntries
    guard
      Self.patchPlacedIdentityTables(
        new: frame.placedTree,
        previous: previous.placedRoot,
        byIdentity: &placedStructuralIndex,
        entries: &placedFrameEntries
      )
    else {
      return nil
    }

    var resolvedByNodeID: [ViewNodeID: ResolvedNode] = [:]
    Self.rebuildNodeIDTable(root: frame.resolvedTree, into: &resolvedByNodeID)

    var measuredByNodeID: [ViewNodeID: MeasuredNode] = [:]
    Self.rebuildNodeIDTable(root: frame.measuredTree, into: &measuredByNodeID)

    var placedByNodeID: [ViewNodeID: PlacedNode] = [:]
    var placedRangesByNodeID: [ViewNodeID: Range<Int>] = [:]
    Self.rebuildPlacedNodeIDTables(
      root: frame.placedTree,
      storage: &placedByNodeID,
      ranges: &placedRangesByNodeID
    )

    self.init(
      resolvedByNodeID: resolvedByNodeID,
      measuredByNodeID: measuredByNodeID,
      placedByNodeID: placedByNodeID,
      structuralFrame: previous.structuralFrame,
      resolvedStructuralIndex: resolvedStructuralIndex,
      measuredStructuralIndex: measuredStructuralIndex,
      placedStructuralIndex: placedStructuralIndex,
      placedRoot: frame.placedTree,
      placedParentByStructuralIdentity: previous.placedParentByStructuralIdentity,
      placedFrameEntries: placedFrameEntries,
      placedFrameEntryRangesByNodeID: placedRangesByNodeID,
      placedFrameEntryRangesByStructuralIdentity:
        previous.placedFrameEntryRangesByStructuralIdentity,
      derivedByPatching: true
    )
  }

  // Each walk below is an explicit-stack pairing (never native recursion —
  // this runs on the small-stack frame-tail worker) that returns `false` on
  // any shape mismatch. Children push reversed so siblings pop in document
  // order, matching the rebuild's depth-first write order.
  //
  // Resolved and placed descent prunes on `==` PLUS a paired `viewNodeID`
  // walk: `ResolvedNode` and `PlacedNode` deliberately exclude `viewNodeID`
  // from `==` (their equivalence currency is content), but the retained
  // node values and the flat placed-entry table carry ids a consumer can
  // read, so a subtree that is content-equal yet re-stamped must still be
  // visited. `MeasuredNode.==` includes `viewNodeID`, so its prune needs no
  // second walk.

  private static func patchResolvedIdentityTable(
    new newRoot: ResolvedNode,
    previous previousRoot: ResolvedNode,
    byIdentity: inout [Identity: ResolvedNode]
  ) -> Bool {
    var pending: [(ResolvedNode, ResolvedNode)] = [(newRoot, previousRoot)]
    while let (new, previous) = pending.popLast() {
      guard
        new.identity == previous.identity,
        new.kind == previous.kind,
        new.structuralPath == previous.structuralPath,
        new.children.count == previous.children.count
      else {
        return false
      }
      if new == previous, pairedViewNodeIDsEqual(new, previous) {
        continue
      }
      byIdentity[new.identity] = new
      for index in new.children.indices.reversed() {
        pending.append((new.children[index], previous.children[index]))
      }
    }
    return true
  }

  private static func patchMeasuredIdentityTable(
    new newRoot: MeasuredNode,
    previous previousRoot: MeasuredNode,
    byIdentity: inout [Identity: MeasuredNode]
  ) -> Bool {
    var pending: [(MeasuredNode, MeasuredNode)] = [(newRoot, previousRoot)]
    while let (new, previous) = pending.popLast() {
      guard
        new.identity == previous.identity,
        new.childMeasurements.count == previous.childMeasurements.count
      else {
        return false
      }
      if new == previous {
        continue
      }
      byIdentity[new.identity] = new
      for index in new.childMeasurements.indices.reversed() {
        pending.append((new.childMeasurements[index], previous.childMeasurements[index]))
      }
    }
    return true
  }

  private static func patchPlacedIdentityTables(
    new newRoot: PlacedNode,
    previous previousRoot: PlacedNode,
    byIdentity: inout [Identity: PlacedNode],
    entries: inout [PlacedFrameTableEntry]
  ) -> Bool {
    var pending: [(PlacedNode, PlacedNode)] = [(newRoot, previousRoot)]
    var nextEntryIndex = 0
    while let (new, previous) = pending.popLast() {
      guard
        new.identity == previous.identity,
        new.children.count == previous.children.count,
        new.subtreeNodeCount == previous.subtreeNodeCount
      else {
        return false
      }
      let entryIndex = nextEntryIndex
      nextEntryIndex += 1
      if new == previous, pairedViewNodeIDsEqual(new, previous) {
        nextEntryIndex += new.subtreeNodeCount - 1
        continue
      }
      guard entryIndex < entries.count else {
        return false
      }
      entries[entryIndex] = .init(
        viewNodeID: new.viewNodeID,
        identity: new.identity,
        bounds: new.bounds,
        namedCoordinateSpace: new.semanticMetadata.namedCoordinateSpace
      )
      byIdentity[new.identity] = new
      for index in new.children.indices.reversed() {
        pending.append((new.children[index], previous.children[index]))
      }
    }
    return true
  }

  /// Paired `viewNodeID` equality over two subtrees already proven
  /// shape-equal by `==` — the strict-fidelity check `ResolvedNode.==` and
  /// `PlacedNode.==` deliberately omit.
  private static func pairedViewNodeIDsEqual(
    _ lhs: ResolvedNode,
    _ rhs: ResolvedNode
  ) -> Bool {
    var pending: [(ResolvedNode, ResolvedNode)] = [(lhs, rhs)]
    while let (lhs, rhs) = pending.popLast() {
      guard lhs.viewNodeID == rhs.viewNodeID else {
        return false
      }
      for index in lhs.children.indices {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }

  private static func pairedViewNodeIDsEqual(
    _ lhs: PlacedNode,
    _ rhs: PlacedNode
  ) -> Bool {
    var pending: [(PlacedNode, PlacedNode)] = [(lhs, rhs)]
    while let (lhs, rhs) = pending.popLast() {
      guard lhs.viewNodeID == rhs.viewNodeID else {
        return false
      }
      for index in lhs.children.indices {
        pending.append((lhs.children[index], rhs.children[index]))
      }
    }
    return true
  }

  // The `ViewNodeID` table rebuilds. Write order is the contract here:
  // storage tables collapse colliding ids by LAST PREORDER writer and the
  // placed range table by LAST POSTORDER writer, exactly as `init(frame:)`'s
  // recursive walks do.

  private static func rebuildNodeIDTable(
    root: ResolvedNode,
    into storage: inout [ViewNodeID: ResolvedNode]
  ) {
    var pending: [ResolvedNode] = [root]
    while let node = pending.popLast() {
      if let viewNodeID = node.viewNodeID {
        storage[viewNodeID] = node
      }
      for index in node.children.indices.reversed() {
        pending.append(node.children[index])
      }
    }
  }

  private static func rebuildNodeIDTable(
    root: MeasuredNode,
    into storage: inout [ViewNodeID: MeasuredNode]
  ) {
    var pending: [MeasuredNode] = [root]
    while let node = pending.popLast() {
      if let viewNodeID = node.viewNodeID {
        storage[viewNodeID] = node
      }
      for index in node.childMeasurements.indices.reversed() {
        pending.append(node.childMeasurements[index])
      }
    }
  }

  private static func rebuildPlacedNodeIDTables(
    root: PlacedNode,
    storage: inout [ViewNodeID: PlacedNode],
    ranges: inout [ViewNodeID: Range<Int>]
  ) {
    enum Phase {
      case enter
      case exit
    }
    var pending: [(PlacedNode, Int, Phase)] = [(root, 0, .enter)]
    var preorderCursor = 0
    while let (node, start, phase) = pending.popLast() {
      switch phase {
      case .enter:
        let entryStart = preorderCursor
        preorderCursor += 1
        if let viewNodeID = node.viewNodeID {
          storage[viewNodeID] = node
        }
        pending.append((node, entryStart, .exit))
        for index in node.children.indices.reversed() {
          pending.append((node.children[index], 0, .enter))
        }
      case .exit:
        if let viewNodeID = node.viewNodeID {
          ranges[viewNodeID] = start..<(start + node.subtreeNodeCount)
        }
      }
    }
  }
}
