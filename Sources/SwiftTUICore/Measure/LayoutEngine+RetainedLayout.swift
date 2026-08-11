extension LayoutEngine {
  // MARK: - Retained layout

  internal struct RetainedPlacementResult {
    var placed: PlacedNode
    var placedFrameFragment: PlacedFrameTableFragment?
  }

  internal func retainedMeasurement(
    for resolved: ResolvedNode,
    proposal: ProposedSize,
    retainedLayout: RetainedLayoutSession?,
    hasInvalidatedIndexedDescendant: Bool,
    passContext: LayoutPassContext? = nil
  ) -> MeasuredNode? {
    guard let retainedLayout,
      !hasInvalidatedIndexedDescendant,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.hasSyntheticInvalidatedAncestor(resolved.identity),
      !retainedLayout.containsInvalidatedDescendant(of: resolved.identity),
      supportsRetainedLayoutReuse(for: resolved),
      let previousResolved = retainedLayout.resolvedNode(for: resolved.identity),
      let previousMeasured = retainedLayout.measuredNode(for: resolved.identity),
      previousMeasured.proposal == proposal,
      previousResolved.isEquivalentForMeasurement(to: resolved)
    else {
      return nil
    }

    // A windowed lazy product (Stage 2.2) is valid only for the hint it was
    // built under: the scroll layout's measurement-reuse signature is
    // deliberately position-free, so an offset change alone would otherwise
    // reuse the stale window. Reuse requires the current hint to equal the
    // stored one exactly AND to be unclaimed; approving claims it, because
    // the reused product stands in for the fresh measure that would have
    // claimed (scroll-latency Stage 2, plan 2026-07-31-002 — the stored
    // hint replaced a stride-based window recompute, which was no longer
    // self-consistent once the stride became a running refinement).
    if let lazySnapshot = previousMeasured.containerAllocationSnapshot?.lazyStack,
      lazySnapshot.measuredWindow != nil
    {
      guard let passContext,
        let storedHint = lazySnapshot.windowHint,
        passContext.currentMeasureViewportHint == storedHint,
        passContext.claimCurrentMeasureViewportHint(for: resolved.identity) == storedHint
      else {
        return nil
      }
    }

    // Same rule for a hint-windowed hosted collection: the stored product is
    // valid only for the window it was measured for, and an offset-only change
    // in the enclosing scroll view does not change anything the equivalence
    // gate above compares. Hosted strides are probe-stable (no running
    // refinement), so the window recompute remains self-consistent here; the
    // claim keeps fresh and reused paths symmetric.
    if let hostedSnapshot = previousMeasured.containerAllocationSnapshot?.hostedCollection,
      let storedWindow = hostedSnapshot.measuredWindow
    {
      guard let passContext,
        let rowStride = hostedSnapshot.estimatedRowStride,
        hostedCollectionHintWindow(
          hint: passContext.currentMeasureViewportHint,
          count: resolved.indexedChildSource?.count ?? 0,
          rowStride: rowStride
        ) == storedWindow,
        passContext.claimCurrentMeasureViewportHint(for: resolved.identity) != nil
      else {
        return nil
      }
    }

    // The equivalence walk above is structural by design, so a pure `.id`
    // change beneath this node (with no invalidation of its own — an ancestor
    // re-resolve can produce exactly that) still serves. Re-stamp the served
    // subtree's identities from the current resolved tree; see
    // `MeasuredNode.restampingIdentities(from:)` for the contract.
    return previousMeasured.restampingIdentities(from: resolved)
  }

  internal func retainedPlacement(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    retainedLayout: RetainedLayoutSession?
  ) -> RetainedPlacementResult? {
    if viewportContext != nil, case .lazyStack = resolved.layoutBehavior {
      return nil
    }
    // Indexed containers compare by the ID-only measurement signature, so a
    // payload-only row change is invisible to `placementEquivalence`; when
    // the invalidation summary marked a source at or below this node,
    // retained placement must yield (the count-mismatch metadata-sync skip
    // below would otherwise serve stale placed children silently).
    if retainedLayout?.affectsIndexedChildSource(within: resolved.identity) == true {
      return nil
    }

    guard
      let retainedLayout,
      !retainedLayout.isDirectlyInvalidated(resolved.identity),
      !retainedLayout.hasSyntheticInvalidatedAncestor(resolved.identity),
      !retainedLayout.containsInvalidatedDescendant(of: resolved.identity),
      supportsRetainedLayoutReuse(for: resolved),
      let previousResolved = retainedLayout.resolvedNode(for: resolved.identity),
      let previousMeasured = retainedLayout.measuredNode(for: resolved.identity),
      let previousPlaced = retainedLayout.placedNode(for: resolved.identity)
    else {
      return nil
    }

    // One walk decides both reuse validity (geometry) and whether the
    // geometry-stable metadata mirrors are also unchanged.
    let equivalence = previousResolved.placementEquivalence(to: resolved)
    guard equivalence != .divergent else {
      return nil
    }

    let measurementMatches = previousMeasured == measured
    let translationMeasurementMatches = isEquivalentForViewportTranslation(
      previousMeasured, measured)

    // `placementEquivalence` deliberately ignores resolved metadata that does
    // not affect geometry so visual, semantic, lifecycle, and animation-tick
    // mutations can reuse cached layout. When the subtree is fully `.identical`,
    // the cached placed subtree already mirrors the current resolved tree, so it
    // is returned untouched — skipping the O(subtree) metadata-sync rebuild that
    // otherwise made placement reuse nearly as costly as recomputation. When
    // only geometry matches (`.geometryReusable`), the mirrors are refreshed
    // from the current resolved tree while preserving cached bounds.
    let skipMetadataSync = equivalence == .identical
    let retainedFrameFragment =
      skipMetadataSync
      ? retainedLayout.placedFrameFragment(for: resolved.identity)
      : nil
    func reuse(_ placed: PlacedNode) -> PlacedNode {
      skipMetadataSync
        ? placed
        : synchronizeRetainedPhaseMetadata(placed: placed, from: resolved)
    }

    if previousPlaced.bounds == bounds {
      guard measurementMatches else {
        return nil
      }
      return .init(
        placed: reuse(previousPlaced),
        placedFrameFragment: retainedFrameFragment
      )
    }

    guard
      viewportContext != nil,
      previousPlaced.bounds.size == bounds.size,
      measurementMatches || translationMeasurementMatches
    else {
      return nil
    }

    let delta = CellPoint(
      x: bounds.origin.x - previousPlaced.bounds.origin.x,
      y: bounds.origin.y - previousPlaced.bounds.origin.y
    )
    if delta == .zero {
      return .init(
        placed: reuse(previousPlaced),
        placedFrameFragment: retainedFrameFragment
      )
    }

    return .init(
      placed: reuse(translatedPlacement(previousPlaced, by: delta)),
      placedFrameFragment: retainedFrameFragment?.translated(by: delta)
    )
  }

  /// Walks a reused placed subtree in parallel with the current
  /// resolved subtree and copies all resolved metadata mirrored by
  /// ``PlacedNode`` from the current resolved node onto the cached
  /// placed node. The trees are guaranteed structurally identical by
  /// `isEquivalentForPlacement`, so we can zip them safely.
  ///
  /// This lets the layout engine reuse cached placement (bounds,
  /// sizes) while still picking up geometry-stable metadata mutations
  /// from the current frame.
  internal func synchronizeRetainedPhaseMetadata(
    placed: PlacedNode,
    from resolved: ResolvedNode
  ) -> PlacedNode {
    // Iterative post-order rebuild for the same reason as `translatedPlacement`:
    // this runs on the frame-tail worker's small stack over node-hosted
    // collection rows and deep custom-layout chains. Completed children are
    // written back into the parent frame's value-typed `children[index]`.
    struct Frame {
      var node: PlacedNode
      let resolved: ResolvedNode
      var nextChildIndex: Int
      /// Structural mismatch — should not happen because
      /// `isEquivalentForPlacement` gated on `children.count`, but play it safe
      /// and stop descending at this node rather than zipping mismatched trees.
      let descendsIntoChildren: Bool
    }

    func makeFrame(_ placed: PlacedNode, _ resolved: ResolvedNode) -> Frame {
      var node = placed
      node.synchronizeResolvedPhaseMetadata(
        from: resolved,
        semanticRole: semanticRole(for: resolved)
      )
      return Frame(
        node: node,
        resolved: resolved,
        nextChildIndex: 0,
        descendsIntoChildren: node.children.count == resolved.children.count
      )
    }

    var stack: [Frame] = [makeFrame(placed, resolved)]
    while true {
      let index = stack.count - 1
      if stack[index].descendsIntoChildren,
        stack[index].nextChildIndex < stack[index].node.children.count
      {
        let childIndex = stack[index].nextChildIndex
        stack.append(
          makeFrame(
            stack[index].node.children[childIndex],
            stack[index].resolved.children[childIndex]
          )
        )
        continue
      }

      let finished = stack.removeLast().node
      guard let parentIndex = stack.indices.last else {
        return finished
      }
      stack[parentIndex].node.children[stack[parentIndex].nextChildIndex] = finished
      stack[parentIndex].nextChildIndex += 1
    }
  }

  internal func isEquivalentForViewportTranslation(
    _ lhs: MeasuredNode,
    _ rhs: MeasuredNode
  ) -> Bool {
    // Heap-backed pair walk; same field contract as the recursion.
    var pending: [(MeasuredNode, MeasuredNode)] = [(lhs, rhs)]
    while let (lhs, rhs) = pending.popLast() {
      guard
        lhs.identity == rhs.identity,
        lhs.measuredSize == rhs.measuredSize,
        lhs.childMeasurements.count == rhs.childMeasurements.count
      else {
        return false
      }
      for index in lhs.childMeasurements.indices.reversed() {
        pending.append((lhs.childMeasurements[index], rhs.childMeasurements[index]))
      }
    }
    return true
  }

  internal func hasInvalidatedIndexedDescendant(
    for resolved: ResolvedNode,
    passContext: LayoutPassContext?
  ) -> Bool {
    guard let retainedLayout = passContext?.retainedLayout else {
      return false
    }

    if let source = resolved.indexedChildSource,
      retainedLayout.affectsIndexedChildSource(root: source.identityRoot)
    {
      return true
    }
    // Ancestors of an affected source must refuse subtree reuse too: their
    // retained comparison is signature-blind inside the indexed container,
    // so an enclosing reuse would serve the stale allocation without the
    // container's own gate ever running.
    return retainedLayout.affectsIndexedChildSource(within: resolved.identity)
  }

  internal func supportsRetainedLayoutReuse(
    for resolved: ResolvedNode
  ) -> Bool {
    resolved.supportsRetainedReuse
  }

  internal func storedChildMeasurements(
    for resolved: ResolvedNode,
    measuredChildren: [MeasuredNode]
  ) -> [MeasuredNode] {
    guard resolved.usesIndexedChildSource, case .lazyStack = resolved.layoutBehavior else {
      return measuredChildren
    }

    return []
  }
}
