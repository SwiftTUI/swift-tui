extension LayoutEngine {
  func placementRequests(
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
      return safeAreaInsetPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        edge: edge,
        alignment: alignment,
        spacing: spacing,
        safeArea: safeArea
      )
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
      return decorationPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        primaryIndex: primaryIndex,
        alignment: alignment,
        passContext: passContext
      )
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
}
