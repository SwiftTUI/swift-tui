public import SwiftTUICore

/// The layout algorithm underlying `HStack`.
public struct HStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: VerticalAlignment
  public var spacing: Int?

  /// Creates a horizontal stack layout.
  public init(
    alignment: VerticalAlignment = .center,
    spacing: Int? = nil
  ) {
    self.alignment = alignment
    self.spacing = spacing
  }

  var builtinLayoutBehavior: LayoutBehavior {
    .stack(
      axis: .horizontal,
      spacing: spacing,
      horizontalAlignment: .center,
      verticalAlignment: alignment
    )
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    simpleStackSize(
      axis: .horizontal,
      horizontalAlignment: .center,
      verticalAlignment: alignment,
      spacing: spacing,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeSimpleStack(
      axis: .horizontal,
      horizontalAlignment: .center,
      verticalAlignment: alignment,
      spacing: spacing,
      in: bounds,
      subviews: subviews
    )
  }
}

/// The layout algorithm underlying `VStack`.
public struct VStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: HorizontalAlignment
  public var spacing: Int?

  /// Creates a vertical stack layout.
  public init(
    alignment: HorizontalAlignment = .center,
    spacing: Int? = nil
  ) {
    self.alignment = alignment
    self.spacing = spacing
  }

  var builtinLayoutBehavior: LayoutBehavior {
    .stack(
      axis: .vertical,
      spacing: spacing,
      horizontalAlignment: alignment,
      verticalAlignment: .center
    )
  }

  public func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    simpleStackSize(
      axis: .vertical,
      horizontalAlignment: alignment,
      verticalAlignment: .center,
      spacing: spacing,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeSimpleStack(
      axis: .vertical,
      horizontalAlignment: alignment,
      verticalAlignment: .center,
      spacing: spacing,
      in: bounds,
      subviews: subviews
    )
  }
}

/// The layout algorithm underlying `ZStack`.
public struct ZStackLayout: Layout, BuiltinLayoutBehaviorProviding {
  public var alignment: Alignment

  /// Creates a z-axis stack layout.
  public init(alignment: Alignment = .center) {
    self.alignment = alignment
  }

  var builtinLayoutBehavior: LayoutBehavior {
    .overlay(alignment: alignment)
  }

  public func sizeThatFits(
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    let dimensions = subviews.map { $0.dimensions(in: .unspecified) }
    let alignmentMetrics = overlayAlignmentMetrics(
      dimensions: dimensions,
      alignment: alignment
    )
    return LayoutSize(
      width: alignmentMetrics.leading + alignmentMetrics.trailing,
      height: alignmentMetrics.top + alignmentMetrics.bottom
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal _: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeOverlaySubviews(
      alignment: alignment,
      in: bounds,
      subviews: subviews
    )
  }
}

private func simpleStackSize(
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment,
  spacing: Int?,
  proposal: ProposedViewSize,
  subviews: LayoutSubviews
) -> LayoutSize {
  let idealProposal: ProposedViewSize =
    switch axis {
    case .horizontal:
      .init(width: .unspecified, height: proposal.height)
    case .vertical:
      .init(width: proposal.width, height: .unspecified)
    }

  let dimensions = subviews.map { $0.dimensions(in: idealProposal) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let stackSpacings = resolvedStackSpacings(
    for: subviews,
    axis: axis,
    spacingOverride: spacing
  )
  let totalSpacing = stackSpacings.reduce(0, +)
  let crossMetrics = stackCrossMetrics(
    dimensions: dimensions,
    axis: axis,
    horizontalAlignment: horizontalAlignment,
    verticalAlignment: verticalAlignment
  )

  switch axis {
  case .horizontal:
    return LayoutSize(
      width: sizes.reduce(0) { $0 + $1.width } + totalSpacing,
      height: crossMetrics.leading + crossMetrics.trailing
    )
  case .vertical:
    return LayoutSize(
      width: crossMetrics.leading + crossMetrics.trailing,
      height: sizes.reduce(0) { $0 + $1.height } + totalSpacing
    )
  }
}

private func placeSimpleStack(
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment,
  spacing: Int?,
  in bounds: LayoutRect,
  subviews: LayoutSubviews
) {
  let idealProposal: ProposedViewSize =
    switch axis {
    case .horizontal:
      .init(width: .unspecified, height: .finite(bounds.size.height))
    case .vertical:
      .init(width: .finite(bounds.size.width), height: .unspecified)
    }

  let dimensions = subviews.map { $0.dimensions(in: idealProposal) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let stackSpacings = resolvedStackSpacings(
    for: subviews,
    axis: axis,
    spacingOverride: spacing
  )
  let crossMetrics = stackCrossMetrics(
    dimensions: dimensions,
    axis: axis,
    horizontalAlignment: horizontalAlignment,
    verticalAlignment: verticalAlignment
  )

  var cursor = axis == .horizontal ? bounds.origin.x : bounds.origin.y
  for (index, subview) in subviews.enumerated() {
    let size = sizes[index]
    let origin =
      switch axis {
      case .horizontal:
        LayoutPoint(
          x: cursor,
          y: bounds.origin.y + crossMetrics.leading - dimensions[index][verticalAlignment]
        )
      case .vertical:
        LayoutPoint(
          x: bounds.origin.x + crossMetrics.leading - dimensions[index][horizontalAlignment],
          y: cursor
        )
      }
    subview.place(
      at: origin,
      anchor: .topLeading,
      proposal: .init(width: size.width, height: size.height)
    )
    cursor += axis == .horizontal ? size.width : size.height
    if index < stackSpacings.count {
      cursor += stackSpacings[index]
    }
  }
}

private func resolvedStackSpacings(
  for subviews: LayoutSubviews,
  axis: Axis,
  spacingOverride: Int?
) -> [Int] {
  guard subviews.count > 1 else {
    return []
  }

  if let spacingOverride {
    return Array(repeating: spacingOverride, count: subviews.count - 1)
  }

  return subviews.indices.dropLast().map { index in
    subviews[index].spacing.distance(
      to: subviews[index + 1].spacing,
      along: axis == .horizontal ? .horizontal : .vertical
    )
  }
}

private func stackCrossMetrics(
  dimensions: [ViewDimensions],
  axis: Axis,
  horizontalAlignment: HorizontalAlignment,
  verticalAlignment: VerticalAlignment
) -> (leading: Int, trailing: Int) {
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

private func overlayAlignmentMetrics(
  dimensions: [ViewDimensions],
  alignment: Alignment
) -> (leading: Int, trailing: Int, top: Int, bottom: Int) {
  let leading = dimensions.map { max(0, $0[alignment.horizontal]) }.max() ?? 0
  let trailing = dimensions.map { max(0, $0.width - $0[alignment.horizontal]) }.max() ?? 0
  let top = dimensions.map { max(0, $0[alignment.vertical]) }.max() ?? 0
  let bottom = dimensions.map { max(0, $0.height - $0[alignment.vertical]) }.max() ?? 0

  return (leading, trailing, top, bottom)
}

private func placeOverlaySubviews(
  alignment: Alignment,
  in bounds: LayoutRect,
  subviews: LayoutSubviews
) {
  let dimensions = subviews.map { $0.dimensions(in: .unspecified) }
  let sizes = dimensions.map { LayoutSize(width: $0.width, height: $0.height) }
  let alignmentMetrics = overlayAlignmentMetrics(
    dimensions: dimensions,
    alignment: alignment
  )

  for (index, subview) in subviews.enumerated() {
    subview.place(
      at: LayoutPoint(
        x: bounds.origin.x + alignmentMetrics.leading - dimensions[index][alignment.horizontal],
        y: bounds.origin.y + alignmentMetrics.top - dimensions[index][alignment.vertical]
      ),
      anchor: .topLeading,
      proposal: .init(width: sizes[index].width, height: sizes[index].height)
    )
  }
}
