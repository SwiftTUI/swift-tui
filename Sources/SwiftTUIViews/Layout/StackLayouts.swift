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
    builtinLayoutSize(
      behavior: builtinLayoutBehavior,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeBuiltinLayoutSubviews(
      behavior: builtinLayoutBehavior,
      in: bounds,
      proposal: proposal,
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
    builtinLayoutSize(
      behavior: builtinLayoutBehavior,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeBuiltinLayoutSubviews(
      behavior: builtinLayoutBehavior,
      in: bounds,
      proposal: proposal,
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
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    builtinLayoutSize(
      behavior: builtinLayoutBehavior,
      proposal: proposal,
      subviews: subviews
    )
  }

  public func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    placeBuiltinLayoutSubviews(
      behavior: builtinLayoutBehavior,
      in: bounds,
      proposal: proposal,
      subviews: subviews
    )
  }
}
