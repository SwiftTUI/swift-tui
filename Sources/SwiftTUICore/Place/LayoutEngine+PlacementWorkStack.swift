private struct PlacementRequest {
  var resolved: ResolvedNode
  var measured: MeasuredNode
  var bounds: CellRect
}

private enum PlacementWorkItem {
  case place(
    ResolvedNode,
    measured: MeasuredNode,
    bounds: CellRect,
    viewportContext: LazyStackViewportContext?
  )
  case finish(
    ResolvedNode,
    measured: MeasuredNode,
    bounds: CellRect,
    childCount: Int
  )
}

extension LayoutEngine {
  package func placeIterative(
    _ resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> PlacedNode {
    var work: [PlacementWorkItem] = [
      .place(
        resolved,
        measured: measured,
        bounds: bounds,
        viewportContext: viewportContext
      )
    ]
    var results: [PlacedNode] = []

    while let item = work.popLast() {
      passContext?.updateWorkMetrics {
        $0.placementWorkStackSteps += 1
      }

      switch item {
      case .place(let node, let measured, let bounds, let viewportContext):
        schedulePlacement(
          of: node,
          measured: measured,
          in: bounds,
          viewportContext: viewportContext,
          passContext: passContext,
          work: &work,
          results: &results
        )
      case .finish(let node, let measured, let bounds, let childCount):
        let children = popPlacements(from: &results, count: childCount)
        results.append(
          placedNode(
            from: node,
            bounds: bounds,
            measured: measured,
            children: children
          )
        )
      }
    }

    precondition(results.count == 1, "placement work stack left \(results.count) roots")
    return results[0]
  }

  private func schedulePlacement(
    of node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?,
    work: inout [PlacementWorkItem],
    results: inout [PlacedNode]
  ) {
    if let retained = retainedPlacement(
      for: node,
      measured: measured,
      bounds: bounds,
      viewportContext: viewportContext,
      retainedLayout: passContext?.retainedLayout
    ) {
      passContext?.updateWorkMetrics {
        $0.placedNodesReused += retained.subtreeNodeCount
      }
      passContext?.recordPlacedFrames(in: retained)
      results.append(retained)
      return
    }

    passContext?.updateWorkMetrics {
      $0.placedNodesComputed += 1
    }

    passContext?.recordPlacedFrame(
      identity: node.identity,
      bounds: bounds,
      namedCoordinateSpaceName: node.semanticMetadata.namedCoordinateSpaceName
    )

    let hasChildren =
      if node.layoutDependentContent != nil {
        true
      } else if let source = node.indexedChildSource {
        source.count > 0
      } else {
        !node.children.isEmpty
      }

    guard hasChildren else {
      results.append(
        placedNode(
          from: node,
          bounds: bounds,
          measured: measured,
          children: []
        )
      )
      return
    }

    if case .custom(let handle) = node.layoutBehavior {
      let children = handle.placeSubviews(
        engine: self,
        node: node,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
      results.append(
        placedNode(
          from: node,
          bounds: bounds,
          measured: measured,
          children: children
        )
      )
      return
    }

    let requests = placementRequests(
      for: node,
      measured: measured,
      in: bounds,
      viewportContext: viewportContext,
      passContext: passContext
    )

    work.append(
      .finish(
        node,
        measured: measured,
        bounds: bounds,
        childCount: requests.count
      )
    )
    let childViewportContext = passContext?.scrollViewportContext
    for request in requests.reversed() {
      work.append(
        .place(
          request.resolved,
          measured: request.measured,
          bounds: request.bounds,
          viewportContext: childViewportContext
        )
      )
    }
  }

  private func placementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    if let boundary = resolved.layoutDependentContent {
      return layoutDependentPlacementRequests(
        boundary,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }

    switch resolved.layoutBehavior {
    case .intrinsic:
      let childCount = min(resolved.children.count, measured.childMeasurements.count)
      return (0..<childCount).map { index in
        let childMeasurement = measured.childMeasurements[index]
        return PlacementRequest(
          resolved: resolved.children[index],
          measured: childMeasurement,
          bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
        )
      }
    case .overlay(let alignment):
      let alignmentMetrics = overlayAlignmentMetrics(
        for: resolved.children,
        childMeasurements: measured.childMeasurements,
        alignment: alignment
      )
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        let childDimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: resolved.children[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + alignmentMetrics.leading - childDimensions[alignment.horizontal],
              y: bounds.origin.y + alignmentMetrics.top - childDimensions[alignment.vertical]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      return stackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .vertical,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center
      )
    case .stack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      return stackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .horizontal,
        spacing: spacing,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment
      )
    case .lazyStack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      return lazyStackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .vertical,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center,
        viewportContext: viewportContext,
        passContext: passContext
      )
    case .lazyStack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      return lazyStackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .horizontal,
        spacing: spacing,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment,
        viewportContext: viewportContext,
        passContext: passContext
      )
    case .padding(let insets):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + insets.leading,
              y: bounds.origin.y + insets.top
            ),
            size: CellSize(
              width: max(0, bounds.size.width - insets.horizontal),
              height: max(0, bounds.size.height - insets.vertical)
            )
          )
        )
      ]
    case .safeAreaIgnoring(let insets):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x - insets.leading,
              y: bounds.origin.y - insets.top
            ),
            size: CellSize(
              width: bounds.size.width + insets.horizontal,
              height: bounds.size.height + insets.vertical
            )
          )
        )
      ]
    case .safeAreaInset(let edge, let alignment, let spacing, let safeArea):
      guard resolved.children.count >= 2, measured.childMeasurements.count >= 2 else {
        return measured.childMeasurements.enumerated().compactMap { index, childMeasurement in
          guard resolved.children.indices.contains(index) else { return nil }
          return PlacementRequest(
            resolved: resolved.children[index],
            measured: childMeasurement,
            bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
          )
        }
      }

      let base = resolved.children[0]
      let inset = resolved.children[1]
      let baseMeasurement = measured.childMeasurements[0]
      let insetMeasurement = measured.childMeasurements[1]
      let insetLength =
        switch edge {
        case .top, .bottom:
          insetMeasurement.measuredSize.height
        case .leading, .trailing:
          insetMeasurement.measuredSize.width
        }
      let consumed = max(0, insetLength + spacing - safeArea.value(for: edge))

      let baseBounds: CellRect =
        switch edge {
        case .top:
          CellRect(
            origin: CellPoint(x: bounds.origin.x, y: bounds.origin.y + consumed),
            size: CellSize(width: bounds.size.width, height: max(0, bounds.size.height - consumed))
          )
        case .leading:
          CellRect(
            origin: CellPoint(x: bounds.origin.x + consumed, y: bounds.origin.y),
            size: CellSize(width: max(0, bounds.size.width - consumed), height: bounds.size.height)
          )
        case .bottom:
          CellRect(
            origin: bounds.origin,
            size: CellSize(width: bounds.size.width, height: max(0, bounds.size.height - consumed))
          )
        case .trailing:
          CellRect(
            origin: bounds.origin,
            size: CellSize(width: max(0, bounds.size.width - consumed), height: bounds.size.height)
          )
        }

      let insetOrigin: CellPoint =
        switch edge {
        case .top:
          CellPoint(
            x: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.width,
              availableSize: bounds.size.width,
              origin: bounds.origin.x,
              alignment: alignment.horizontal,
              hasExplicitGuide: false
            ) ?? bounds.origin.x,
            y: bounds.origin.y - safeArea.top
          )
        case .bottom:
          CellPoint(
            x: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.width,
              availableSize: bounds.size.width,
              origin: bounds.origin.x,
              alignment: alignment.horizontal,
              hasExplicitGuide: false
            ) ?? bounds.origin.x,
            y: bounds.maxY - insetMeasurement.measuredSize.height + safeArea.bottom
          )
        case .leading:
          CellPoint(
            x: bounds.origin.x - safeArea.leading,
            y: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.height,
              availableSize: bounds.size.height,
              origin: bounds.origin.y,
              alignment: alignment.vertical,
              hasExplicitGuide: false
            ) ?? bounds.origin.y
          )
        case .trailing:
          CellPoint(
            x: bounds.maxX - insetMeasurement.measuredSize.width + safeArea.trailing,
            y: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.height,
              availableSize: bounds.size.height,
              origin: bounds.origin.y,
              alignment: alignment.vertical,
              hasExplicitGuide: false
            ) ?? bounds.origin.y
          )
        }

      return [
        .init(resolved: base, measured: baseMeasurement, bounds: baseBounds),
        .init(
          resolved: inset,
          measured: insetMeasurement,
          bounds: CellRect(origin: insetOrigin, size: insetMeasurement.measuredSize)
        ),
      ]
    case .border(let set, let placement, _, _, _, _, let sides):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let insets = borderLayoutInsets(
        set: set,
        placement: placement,
        sides: sides
      )
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + insets.leading,
              y: bounds.origin.y + insets.top
            ),
            size: CellSize(
              width: max(0, bounds.size.width - insets.horizontal),
              height: max(0, bounds.size.height - insets.vertical)
            )
          )
        )
      ]
    case .frame(_, _, let alignment), .flexibleFrame(_, _, _, _, _, _, let alignment):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let childOrigin =
        simpleAlignedOrigin(
          for: child,
          measured: childMeasurement,
          in: bounds,
          alignment: alignment
        )
        ?? alignedOrigin(
          for: viewDimensions(for: child, measured: childMeasurement),
          in: bounds,
          alignment: alignment
        )
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(origin: childOrigin, size: childMeasurement.measuredSize)
        )
      ]
    case .offset(let x, let y):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: .init(
              x: bounds.origin.x + x,
              y: bounds.origin.y + y
            ),
            size: childMeasurement.measuredSize
          )
        )
      ]
    case .position(let x, let y):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }
      let childSize = childMeasurement.measuredSize
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: .init(
              x: bounds.origin.x + x - childSize.width / 2,
              y: bounds.origin.y + y - childSize.height / 2
            ),
            size: childSize
          )
        )
      ]
    case .decoration(let primaryIndex, let alignment):
      guard
        resolved.children.indices.contains(primaryIndex),
        measured.childMeasurements.indices.contains(primaryIndex)
      else {
        return []
      }

      let primaryDimensions = viewDimensions(
        for: resolved.children[primaryIndex],
        measured: measured.childMeasurements[primaryIndex]
      )
      let primaryOrigin = alignedOrigin(
        for: primaryDimensions,
        referenceDimensions: primaryDimensions,
        in: bounds,
        alignment: alignment
      )
      passContext?.recordPlacedFrame(
        identity: resolved.children[primaryIndex].identity,
        bounds: CellRect(
          origin: primaryOrigin,
          size: measured.childMeasurements[primaryIndex].measuredSize
        ),
        namedCoordinateSpaceName: resolved.children[primaryIndex]
          .semanticMetadata.namedCoordinateSpaceName
      )

      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        let childDimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        let childOrigin = alignedOrigin(
          for: childDimensions,
          referenceDimensions: primaryDimensions,
          in: bounds,
          alignment: alignment
        )
        return PlacementRequest(
          resolved: resolved.children[index],
          measured: childMeasurement,
          bounds: CellRect(origin: childOrigin, size: childMeasurement.measuredSize)
        )
      }
    case .viewThatFits:
      guard
        let selectedIndex = measured.containerAllocationSnapshot?.selectedChildIndex,
        measured.childMeasurements.indices.contains(selectedIndex),
        resolved.children.indices.contains(selectedIndex)
      else {
        return []
      }

      let childMeasurement = measured.childMeasurements[selectedIndex]
      return [
        .init(
          resolved: resolved.children[selectedIndex],
          measured: childMeasurement,
          bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
        )
      ]
    case .custom:
      return []
    }
  }

  private func layoutDependentPlacementRequests(
    _ boundary: LayoutDependentContentBoundary,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    let realizationContext = LayoutRealizationContext(
      boundaryIdentity: boundary.identity,
      proposal: measured.proposal,
      bounds: bounds,
      safeAreaInsets: boundary.safeAreaInsets,
      cellPixelMetrics: boundary.cellPixelMetrics,
      pointerInputCapabilities: boundary.pointerInputCapabilities,
      placedFrameTable: passContext?.placedFrameTable ?? .init()
    )
    let realizedChildren =
      passContext?.realizeLayoutDependentContent(
        in: realizationContext,
        using: {
          boundary.handle.realize(in: realizationContext)
        }
      ) ?? boundary.handle.realize(in: realizationContext)
    let childProposal = ProposedSize(
      width: .finite(bounds.size.width),
      height: .finite(bounds.size.height)
    )

    return realizedChildren.map { child in
      let childMeasurement = measure(
        child,
        proposal: childProposal,
        passContext: passContext
      )
      return PlacementRequest(
        resolved: child,
        measured: childMeasurement,
        bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
      )
    }
  }

  private func stackPlacementRequests(
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

  private func lazyStackPlacementRequests(
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
    if let source = resolved.indexedChildSource,
      let allocation = measured.containerAllocationSnapshot,
      let snapshot = allocation.lazyStack,
      allocation.childSizes.count == source.count
    {
      let visibleRange =
        viewportContext.flatMap {
          lazyStackVisibleChildRange(
            for: snapshot,
            viewportContext: $0,
            overscan: 0
          )
        } ?? (0..<source.count)

      return indexedLazyStackPlacementRequests(
        source: source,
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
    source: any IndexedChildSource,
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
      let child = source.child(at: index)
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

  private func popPlacements(
    from results: inout [PlacedNode],
    count: Int
  ) -> [PlacedNode] {
    guard count > 0 else {
      return []
    }
    precondition(results.count >= count, "placement work stack expected \(count) child results")
    let start = results.count - count
    let children = Array(results[start..<results.count])
    results.removeLast(count)
    return children
  }
}
