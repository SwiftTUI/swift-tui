public struct LayoutEngine: Sendable {
  public let cache: MeasurementCache?

  /// Creates a layout engine with an optional retained measurement cache.
  public init(cache: MeasurementCache? = nil) {
    self.cache = cache
  }

  /// Measures a resolved tree under `proposal`.
  public func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> MeasuredNode {
    measure(
      resolved,
      proposal: proposal,
      passContext: nil
    )
  }

  package func measure(
    _ resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified,
    passContext: LayoutPassContext?
  ) -> MeasuredNode {
    let hasInvalidatedIndexedDescendant = hasInvalidatedIndexedDescendant(
      for: resolved,
      passContext: passContext
    )

    if let retained = retainedMeasurement(
      for: resolved,
      proposal: proposal,
      retainedLayout: passContext?.retainedLayout,
      hasInvalidatedIndexedDescendant: hasInvalidatedIndexedDescendant
    ) {
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += retained.subtreeNodeCount
      }
      return retained
    }

    if !hasInvalidatedIndexedDescendant,
      let cached = cache?.lookup(resolved: resolved, proposal: proposal)
    {
      passContext?.updateWorkMetrics {
        $0.measuredNodesReused += cached.subtreeNodeCount
      }
      return cached
    }

    passContext?.updateWorkMetrics {
      $0.measuredNodesComputed += 1
    }

    if let boundary = resolved.layoutDependentContent {
      let node = MeasuredNode(
        identity: resolved.identity,
        proposal: proposal,
        measuredSize: boundary.sizingPolicy.measuredSize(for: proposal),
        childMeasurements: [],
        containerAllocationSnapshot: nil
      )
      cache?.store(node, for: resolved)
      return node
    }

    let effectiveProposal = proposalApplyingFixedSizeMetadata(
      resolved.layoutMetadata,
      to: proposal
    )
    let childMeasurements = measureChildren(
      for: resolved,
      parentProposal: effectiveProposal,
      passContext: passContext
    )
    let storedChildMeasurements = storedChildMeasurements(
      for: resolved,
      measuredChildren: childMeasurements
    )
    let clampingProposal = clampingProposal(
      for: resolved,
      effectiveProposal: effectiveProposal
    )
    let node = MeasuredNode(
      identity: resolved.identity,
      proposal: proposal,
      measuredSize: clampedSize(
        measuredSize(
          for: resolved,
          childMeasurements: childMeasurements,
          proposal: effectiveProposal,
          passContext: passContext
        ),
        proposal: clampingProposal
      ),
      childMeasurements: storedChildMeasurements,
      containerAllocationSnapshot: containerAllocationSnapshot(
        for: resolved,
        childMeasurements: childMeasurements,
        proposal: effectiveProposal,
        passContext: passContext
      )
    )
    cache?.store(node, for: resolved)
    return node
  }

  /// Places a measured tree at `origin`.
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      passContext: nil
    )
  }

  /// Places a measured tree inside `bounds`.
  public func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    origin: CellPoint = .zero,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: CellRect(origin: origin, size: measured.measuredSize),
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    place(
      resolved,
      measured: measured,
      in: bounds,
      viewportContext: passContext?.scrollViewportContext,
      passContext: passContext
    )
  }

  package func place(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext? = nil
  ) -> PlacedNode {
    if let retained = retainedPlacement(
      for: resolved,
      measured: measured,
      bounds: bounds,
      viewportContext: viewportContext,
      retainedLayout: passContext?.retainedLayout
    ) {
      passContext?.updateWorkMetrics {
        $0.placedNodesReused += retained.subtreeNodeCount
      }
      passContext?.recordPlacedFrames(in: retained)
      return retained
    }

    passContext?.updateWorkMetrics {
      $0.placedNodesComputed += 1
    }

    passContext?.recordPlacedFrame(
      identity: resolved.identity,
      bounds: bounds,
      namedCoordinateSpaceName: resolved.semanticMetadata.namedCoordinateSpaceName
    )

    let hasChildren =
      if resolved.layoutDependentContent != nil {
        true
      } else if let source = resolved.indexedChildSource {
        source.count > 0
      } else {
        !resolved.children.isEmpty
      }

    if !hasChildren {
      return placedNode(
        from: resolved,
        bounds: bounds,
        measured: measured,
        children: []
      )
    }

    let placedChildren = childPlacements(
      for: resolved,
      measured: measured,
      in: bounds,
      viewportContext: viewportContext,
      passContext: passContext
    )

    return placedNode(
      from: resolved,
      bounds: bounds,
      measured: measured,
      children: placedChildren
    )
  }

  public func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize = .unspecified
  ) -> ViewDimensions {
    dimensions(of: resolved, proposal: proposal, passContext: nil)
  }

  package func dimensions(
    of resolved: ResolvedNode,
    proposal: ProposedSize,
    passContext: LayoutPassContext?
  ) -> ViewDimensions {
    let measured = measure(resolved, proposal: proposal, passContext: passContext)
    return viewDimensions(for: resolved, measured: measured)
  }

}
