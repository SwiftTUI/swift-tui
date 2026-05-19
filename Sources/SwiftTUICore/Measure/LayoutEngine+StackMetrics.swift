extension LayoutEngine {
  package func resolvedStackSpacings(
    for children: [ResolvedNode],
    axis: Axis,
    spacingOverride: Int?
  ) -> [Int] {
    guard children.count > 1 else {
      return []
    }

    if let spacingOverride {
      return Array(repeating: spacingOverride, count: children.count - 1)
    }

    return children.indices.dropLast().map { index in
      preferredSpacingDistance(
        from: children[index].layoutMetadata.spacing,
        to: children[index + 1].layoutMetadata.spacing,
        axis: axis
      )
    }
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
    verticalAlignment: VerticalAlignment
  ) -> (leading: Int, trailing: Int) {
    let dimensions = zip(children, childMeasurements).map { child, measurement in
      viewDimensions(for: child, measured: measurement)
    }

    switch axis {
    case .horizontal:
      let leading = dimensions.map { max(0, $0[verticalAlignment]) }.max() ?? 0
      let trailing = dimensions.map { max(0, $0.height - $0[verticalAlignment]) }.max() ?? 0
      return (leading, trailing)
    case .vertical:
      let leading = dimensions.map { max(0, $0[horizontalAlignment]) }.max() ?? 0
      let trailing = dimensions.map { max(0, $0.width - $0[horizontalAlignment]) }.max() ?? 0
      return (leading, trailing)
    }
  }
}
