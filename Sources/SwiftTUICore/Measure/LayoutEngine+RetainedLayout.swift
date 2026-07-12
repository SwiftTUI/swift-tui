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
    hasInvalidatedIndexedDescendant: Bool
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

    return previousMeasured
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
    var node = placed
    node.synchronizeResolvedPhaseMetadata(
      from: resolved,
      semanticRole: semanticRole(for: resolved)
    )

    guard node.children.count == resolved.children.count else {
      // Structural mismatch — should not happen because
      // isEquivalentForPlacement gated on children.count, but play
      // it safe and return the node without recursing further.
      return node
    }
    let refreshedChildren = zip(node.children, resolved.children).map {
      (placedChild, resolvedChild) in
      synchronizeRetainedPhaseMetadata(placed: placedChild, from: resolvedChild)
    }
    node.children = refreshedChildren
    return node
  }

  internal func isEquivalentForViewportTranslation(
    _ lhs: MeasuredNode,
    _ rhs: MeasuredNode
  ) -> Bool {
    lhs.identity == rhs.identity
      && lhs.measuredSize == rhs.measuredSize
      && lhs.childMeasurements.count == rhs.childMeasurements.count
      && zip(lhs.childMeasurements, rhs.childMeasurements).allSatisfy {
        isEquivalentForViewportTranslation($0, $1)
      }
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
