extension LayoutEngine {
  package func resolvedStackSpacings(
    for children: [ResolvedNode],
    axis: Axis,
    spacingOverride: Int?,
    passContext: LayoutPassContext? = nil
  ) -> [Int] {
    guard children.count > 1 else {
      return []
    }

    if let spacingOverride {
      return Array(repeating: spacingOverride, count: children.count - 1)
    }

    let spacings = children.map { child in
      effectiveSpacing(for: child, passContext: passContext)
    }
    return children.indices.dropLast().map { index in
      preferredSpacingDistance(
        from: spacings[index],
        to: spacings[index + 1],
        axis: axis
      )
    }
  }

  /// The spacing preference `node` presents to the container negotiating a
  /// gap next to it (plan 2026-08-31-001). A custom-layout container answers
  /// through its `Layout.spacing(subviews:cache:)` hook; any spacing carried
  /// by the node's own modifier metadata overrides that answer per axis, the
  /// same precedence an `alignmentGuide` modifier has over a container's
  /// explicit alignment. Every other node presents its metadata spacing, as
  /// before. Read at the stack's direct child: a wrapper (`padding`,
  /// `frame`) around a container presents the wrapper's metadata, not the
  /// container's declaration.
  package func effectiveSpacing(
    for node: ResolvedNode,
    passContext: LayoutPassContext?
  ) -> Spacing {
    guard case .custom(let token) = node.layoutBehavior,
      let handle = token as? CustomLayoutHandle,
      let declared = handle.preferredSpacing(engine: self, node: node, passContext: passContext)
    else {
      return node.layoutMetadata.spacing
    }
    return declared.merging(node.layoutMetadata.spacing)
  }

  package func preferredSpacingDistance(
    from current: Spacing,
    to next: Spacing,
    axis: Axis
  ) -> Int {
    switch axis {
    case .horizontal:
      return max(current.horizontal ?? 1, next.horizontal ?? 1)
    case .vertical:
      return max(current.vertical ?? 0, next.vertical ?? 0)
    }
  }

  package func stackCrossMetrics(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    passContext: LayoutPassContext? = nil
  ) -> AlignmentLine {
    let dimensions = zip(children, childMeasurements).map { child, measurement in
      viewDimensions(for: child, measured: measurement, passContext: passContext)
    }

    switch axis {
    case .horizontal:
      return AlignmentLine(
        guides: dimensions.map {
          let position = $0.halfCellPosition(of: verticalAlignment)
          return (position.value, position.isHalfCell, $0.height)
        })
    case .vertical:
      return AlignmentLine(
        guides: dimensions.map {
          let position = $0.halfCellPosition(of: horizontalAlignment)
          return (position.value, position.isHalfCell, $0.width)
        })
    }
  }
}
