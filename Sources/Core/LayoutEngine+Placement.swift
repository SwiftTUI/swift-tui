extension LayoutEngine {
  package func childPlacements(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    switch resolved.layoutBehavior {
    case .intrinsic:
      let childCount = min(resolved.children.count, measured.childMeasurements.count)
      var placements: [PlacedNode] = []
      placements.reserveCapacity(childCount)
      for index in 0..<childCount {
        let childMeasurement = measured.childMeasurements[index]
        placements.append(
          place(
            resolved.children[index],
            measured: childMeasurement,
            in: Rect(origin: bounds.origin, size: childMeasurement.measuredSize),
            passContext: passContext
          )
        )
      }
      return placements
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
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: bounds.origin.x + alignmentMetrics.leading - childDimensions[alignment.horizontal],
              y: bounds.origin.y + alignmentMetrics.top - childDimensions[alignment.vertical]
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      let stackSpacings = resolvedStackSpacings(
        for: resolved.children,
        axis: .vertical,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: resolved.children,
        childMeasurements: measured.childMeasurements,
        axis: .vertical,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center
      )
      var nextY = bounds.origin.y
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextY += childMeasurement.measuredSize.height
          if index < stackSpacings.count {
            nextY += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: nextY
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .stack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      let stackSpacings = resolvedStackSpacings(
        for: resolved.children,
        axis: .horizontal,
        spacingOverride: spacing
      )
      let crossMetrics = stackCrossMetrics(
        for: resolved.children,
        childMeasurements: measured.childMeasurements,
        axis: .horizontal,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment
      )
      var nextX = bounds.origin.x
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextX += childMeasurement.measuredSize.width
          if index < stackSpacings.count {
            nextX += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: nextX,
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .padding(let insets):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let childBounds = Rect(
        origin: Point(
          x: bounds.origin.x + insets.leading,
          y: bounds.origin.y + insets.top
        ),
        size: Size(
          width: max(0, bounds.size.width - insets.horizontal),
          height: max(0, bounds.size.height - insets.vertical)
        )
      )

      return [
        place(
          child,
          measured: childMeasurement,
          in: childBounds,
          passContext: passContext
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
        place(
          child,
          measured: childMeasurement,
          in: Rect(
            origin: childOrigin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
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
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: childOrigin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
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
        place(
          resolved.children[selectedIndex],
          measured: childMeasurement,
          in: Rect(
            origin: bounds.origin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      ]
    case .custom(let handle):
      return handle.proxy.placeSubviews(
        engine: self,
        node: resolved,
        measured: measured,
        in: bounds
      )
    }
  }

  package func placedNode(
    from resolved: ResolvedNode,
    bounds: Rect,
    children: [PlacedNode]
  ) -> PlacedNode {
    let contentBounds = resolvedContentBounds(
      for: resolved,
      bounds: bounds,
      children: children
    )

    return PlacedNode(
      identity: resolved.identity,
      kind: resolved.kind,
      environmentSnapshot: resolved.environmentSnapshot,
      bounds: bounds,
      contentBounds: contentBounds,
      children: children,
      semanticRole: semanticRole(for: resolved),
      layoutMetadata: resolved.layoutMetadata,
      drawMetadata: resolved.drawMetadata,
      semanticMetadata: resolved.semanticMetadata,
      drawPayload: resolved.drawPayload
    )
  }

  package func combinedContentBounds(
    parentBounds: Rect,
    children: [PlacedNode]
  ) -> Rect {
    children.reduce(parentBounds) { partial, child in
      union(partial, child.contentBounds)
    }
  }

  package func union(
    _ lhs: Rect,
    _ rhs: Rect
  ) -> Rect {
    let minX = min(lhs.origin.x, rhs.origin.x)
    let minY = min(lhs.origin.y, rhs.origin.y)
    let maxX = max(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
    let maxY = max(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)

    return Rect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }

  package func resolvedContentBounds(
    for resolved: ResolvedNode,
    bounds: Rect,
    children: [PlacedNode]
  ) -> Rect {
    let childContentBounds = combinedContentBounds(
      parentBounds: bounds,
      children: children
    )

    switch resolved.drawPayload {
    case .image:
      return childContentBounds
    case .list(let payload):
      return union(
        childContentBounds,
        Rect(
          origin: bounds.origin,
          size: measuredListIdealSize(for: payload)
        )
      )
    case .table(let payload):
      return union(
        childContentBounds,
        Rect(
          origin: bounds.origin,
          size: measuredTableIdealSize(for: payload)
        )
      )
    default:
      return childContentBounds
    }
  }

  package func semanticRole(for resolved: ResolvedNode) -> SemanticRole {
    if resolved.semanticMetadata.scrollRole != nil {
      return .scroll
    }
    if resolved.participatesInTopLevelFocus
      || resolved.semanticMetadata.participatesInPointerHitTesting
    {
      return .control
    }
    switch resolved.layoutBehavior {
    case .stack, .overlay, .padding, .frame, .flexibleFrame, .decoration, .viewThatFits, .custom:
      return .container
    case .intrinsic:
      return .generic
    }
  }
}
