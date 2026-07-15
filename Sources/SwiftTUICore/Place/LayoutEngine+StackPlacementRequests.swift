extension LayoutEngine {
  func stackPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  ) -> [PlacementRequest] {
    let stackChildren = stackChildren(for: resolved)
    let stackSpacings = resolvedStackSpacings(
      for: stackChildren,
      axis: axis,
      spacingOverride: spacing
    )
    let crossMetrics = stackCrossMetrics(
      for: stackChildren,
      childMeasurements: measured.childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    switch axis {
    case .vertical:
      var nextY = bounds.origin.y
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextY += childMeasurement.measuredSize.height
          if index < stackSpacings.count {
            nextY += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: nextY
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .horizontal:
      var nextX = bounds.origin.x
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextX += childMeasurement.measuredSize.width
          if index < stackSpacings.count {
            nextX += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: nextX,
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    }
  }

  func lazyStackPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    if resolved.indexedChildSource != nil,
      let allocation = measured.containerAllocationSnapshot,
      allocation.lazyStack != nil,
      allocation.childSizes.count != stackChildren(for: resolved).count
    {
      // The allocation snapshot indexes a different flattened child count
      // than this resolve produced — the indexed-lazy fast path below would
      // place against the wrong rows. Record it; the non-indexed fallback
      // at the bottom still places every realized child (never an empty
      // placement).
      passContext?.recordPlacementChildMismatch(
        identity: resolved.identity,
        behavior: "indexedLazyStack",
        childCount: stackChildren(for: resolved).count,
        measurementCount: allocation.childSizes.count
      )
    }
    if resolved.indexedChildSource != nil,
      let allocation = measured.containerAllocationSnapshot,
      let snapshot = allocation.lazyStack,
      // Flattened cells: a multi-view element contributes one cell per
      // spliced child, so the allocation arrays index the flattened list,
      // not the element list.
      case let flattenedChildren = stackChildren(for: resolved),
      allocation.childSizes.count == flattenedChildren.count
    {
      let visibleRange =
        viewportContext.flatMap {
          lazyStackVisibleChildRange(
            for: snapshot,
            in: bounds,
            viewportContext: $0,
            overscan: 0
          )
        } ?? (0..<flattenedChildren.count)

      return indexedLazyStackPlacementRequests(
        children: flattenedChildren,
        childSizes: allocation.childSizes,
        measured: measured,
        in: bounds,
        axis: axis,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment,
        snapshot: snapshot,
        visibleRange: visibleRange,
        passContext: passContext
      )
    }

    let stackChildren = stackChildren(for: resolved)
    guard let viewportContext,
      let snapshot = measured.containerAllocationSnapshot?.lazyStack,
      let visibleRange = lazyStackVisibleChildRange(
        for: snapshot,
        in: bounds,
        viewportContext: viewportContext
      )
    else {
      return stackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: axis,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment
      )
    }

    let crossMetrics = stackCrossMetrics(
      for: stackChildren,
      childMeasurements: measured.childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    switch axis {
    case .vertical:
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: bounds.origin.y + snapshot.childMainOffsets[index]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .horizontal:
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + snapshot.childMainOffsets[index],
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    }
  }

  private func indexedLazyStackPlacementRequests(
    children: [ResolvedNode],
    childSizes: [ChildAllocation],
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    snapshot: LazyStackAllocationSnapshot,
    visibleRange: Range<Int>,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    visibleRange.map { index in
      let child = children[index]
      let childSize = childSizes[index].size
      var childMeasurement = measure(
        child,
        proposal: stackProposal(
          axis: axis,
          main: .finite(mainDimension(of: childSize, for: axis)),
          cross: crossDimension(of: measured.proposal, for: axis)
        ),
        passContext: passContext
      )
      if isSpacer(child) {
        childMeasurement.measuredSize = settingMainDimension(
          of: childMeasurement.measuredSize,
          for: axis,
          to: mainDimension(of: childSize, for: axis)
        )
      }
      let dimensions = viewDimensions(
        for: child,
        measured: childMeasurement
      )

      let origin: CellPoint =
        switch axis {
        case .vertical:
          .init(
            x: bounds.origin.x + snapshot.crossLeading - dimensions[horizontalAlignment],
            y: bounds.origin.y + snapshot.childMainOffsets[index]
          )
        case .horizontal:
          .init(
            x: bounds.origin.x + snapshot.childMainOffsets[index],
            y: bounds.origin.y + snapshot.crossLeading - dimensions[verticalAlignment]
          )
        }

      return PlacementRequest(
        resolved: child,
        measured: childMeasurement,
        bounds: CellRect(origin: origin, size: childMeasurement.measuredSize)
      )
    }
  }
}
