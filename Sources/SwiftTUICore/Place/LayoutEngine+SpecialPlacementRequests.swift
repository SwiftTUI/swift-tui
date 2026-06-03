// Special-case placement-request builders for the layout engine.
//
// `placementRequests(...)` (in `LayoutEngine+PlacementRequests.swift`) handles
// the common layout behaviors directly and delegates three structurally
// distinct cases here:
//
//  - `safeAreaInset` — a base view inset by a sibling pinned to one edge,
//  - `decoration` — siblings aligned against one designated primary child,
//  - layout-dependent content — children realized only once their container's
//    bounds are known.
//
// These are file-internal rather than `private` so the dispatcher can reach
// them across files.
extension LayoutEngine {
  func safeAreaInsetPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    edge: Edge,
    alignment: Alignment,
    spacing: Int,
    safeArea: EdgeInsets
  ) -> [PlacementRequest] {
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
  }

  func decorationPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    primaryIndex: Int,
    alignment: Alignment,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
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
      viewNodeID: resolved.children[primaryIndex].viewNodeID,
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
  }

  func layoutDependentPlacementRequests(
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
}
