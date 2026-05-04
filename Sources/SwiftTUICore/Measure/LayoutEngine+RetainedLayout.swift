extension LayoutEngine {
  // MARK: - Retained layout

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
  ) -> PlacedNode? {
    if viewportContext != nil, case .lazyStack = resolved.layoutBehavior {
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
      let previousPlaced = retainedLayout.placedNode(for: resolved.identity),
      previousResolved.isEquivalentForPlacement(to: resolved)
    else {
      return nil
    }

    let measurementMatches = previousMeasured == measured
    let translationMeasurementMatches = isEquivalentForViewportTranslation(
      previousMeasured, measured)

    if previousPlaced.bounds == bounds {
      guard measurementMatches else {
        return nil
      }
      // `isEquivalentForPlacement` deliberately ignores `drawMetadata`
      // so that visual-only mutations — animation controller color
      // interpolation in particular — don't invalidate layout reuse.
      // But that means the cached `previousPlaced` carries the
      // PREVIOUS frame's drawMetadata, which is wrong for any tick
      // frame where the controller mutated colors/opacity/padding
      // on the resolved tree.  Refresh the visual metadata from the
      // current resolved tree while preserving the cached bounds.
      return refreshDrawMetadata(placed: previousPlaced, from: resolved)
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
      return refreshDrawMetadata(placed: previousPlaced, from: resolved)
    }

    return refreshDrawMetadata(
      placed: translatedPlacement(previousPlaced, by: delta),
      from: resolved
    )
  }

  /// Walks a reused placed subtree in parallel with the current
  /// resolved subtree and copies visual metadata (drawMetadata,
  /// semanticMetadata, lifecycleMetadata, environmentSnapshot,
  /// isTransient) from the current resolved node onto the cached
  /// placed node.  The trees are guaranteed structurally identical
  /// by `isEquivalentForPlacement`, so we can zip them safely.
  ///
  /// This lets the layout engine reuse cached placement (bounds,
  /// sizes) while still picking up tick-frame visual mutations from
  /// the animation controller.
  internal func refreshDrawMetadata(
    placed: PlacedNode,
    from resolved: ResolvedNode
  ) -> PlacedNode {
    var node = placed
    node.drawMetadata = resolved.drawMetadata
    node.semanticMetadata = resolved.semanticMetadata
    node.lifecycleMetadata = resolved.lifecycleMetadata
    node.environmentSnapshot = resolved.environmentSnapshot
    node.layoutBehavior = resolved.layoutBehavior
    node.isTransient = resolved.isTransient
    node.matchedGeometry = resolved.matchedGeometry

    guard node.children.count == resolved.children.count else {
      // Structural mismatch — should not happen because
      // isEquivalentForPlacement gated on children.count, but play
      // it safe and return the node without recursing further.
      return node
    }
    let refreshedChildren = zip(node.children, resolved.children).map {
      (placedChild, resolvedChild) in
      refreshDrawMetadata(placed: placedChild, from: resolvedChild)
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
    guard let source = resolved.indexedChildSource else {
      return false
    }

    guard let retainedLayout = passContext?.retainedLayout else {
      return false
    }

    return retainedLayout.affectsIndexedChildSource(root: source.identityRoot)
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
