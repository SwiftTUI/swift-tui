import SwiftTUICore

// The scroll view's layout.
//
// `ScrollViewLayout` measures its single content child, reserves space for
// scroll indicators when they are shown, clamps the requested scroll offset to
// the scrollable range, and places the content within the viewport. The
// indicator-inset measurement iterates because reserving an indicator can
// itself change whether the *other* axis overflows.
//
// Split out of `ScrollView.swift` so that file stays focused on the public
// `ScrollView` view. Widened from `private` to file-internal: `ScrollView`
// constructs `ScrollViewLayout` in its `resolve` method, so the type and its
// memberwise initializer must be visible across the two files. The nested
// `IndicatorInsets` stays `private` — nothing outside this layout uses it.

struct ScrollViewLayout: Layout, StackMinimumLayoutProviding {
  private struct IndicatorInsets: Equatable {
    var trailing: Int = 0
    var bottom: Int = 0
  }

  var axes: Axis.Set
  var position: ScrollPosition
  var showsIndicators: Bool
  func makeCache(subviews _: LayoutSubviews) {}

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize
  ) -> Int? {
    switch axis {
    case .horizontal:
      return axes.contains(.horizontal) ? nil : idealSize.width
    case .vertical:
      return axes.contains(.vertical) ? nil : idealSize.height
    }
  }

  func sizeThatFits(
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) -> LayoutSize {
    guard let subview = subviews.first else {
      return .zero
    }

    let measurement = measuredContent(for: proposal, subview: subview)
    let childSize = measurement.childSize
    let indicatorInsets = measurement.indicatorInsets

    return .init(
      width: viewportDimension(
        childSize.width,
        proposal: proposal.width,
        scrollsAlong: axes.contains(.horizontal),
        reserved: indicatorInsets.trailing
      ),
      height: viewportDimension(
        childSize.height,
        proposal: proposal.height,
        scrollsAlong: axes.contains(.vertical),
        reserved: indicatorInsets.bottom
      )
    )
  }

  func placeSubviews(
    in bounds: LayoutRect,
    proposal: ProposedViewSize,
    subviews: LayoutSubviews,
    cache _: inout Void
  ) {
    guard let subview = subviews.first else {
      return
    }

    let measurement = measuredContent(for: proposal, subview: subview)
    let childSize = measurement.childSize
    let indicatorInsets = measurement.indicatorInsets
    let viewportBounds = contentViewport(in: bounds, indicatorInsets: indicatorInsets)
    let clampedOffset = contentOffset(
      childSize: childSize,
      viewportSize: viewportBounds.size
    )
    subview.place(
      at: .init(
        x: viewportBounds.origin.x - clampedOffset.x,
        y: viewportBounds.origin.y - clampedOffset.y
      ),
      anchor: .topLeading,
      proposal: .init(width: childSize.width, height: childSize.height),
      viewportContext: .init(
        axes: axes,
        viewportRect: viewportBounds,
        contentOffset: .init(x: clampedOffset.x, y: clampedOffset.y)
      )
    )
  }

  private func contentProposal(
    for proposal: ProposedViewSize,
    indicatorInsets: IndicatorInsets
  ) -> ProposedViewSize {
    .init(
      width: axes.contains(.horizontal)
        ? .unspecified
        : reducedDimension(proposal.width, by: indicatorInsets.trailing),
      height: axes.contains(.vertical)
        ? .unspecified
        : reducedDimension(proposal.height, by: indicatorInsets.bottom)
    )
  }

  private func viewportDimension(
    _ child: Int,
    proposal: ProposedDimension,
    scrollsAlong axis: Bool,
    reserved: Int
  ) -> Int {
    switch proposal {
    case .unspecified:
      return child + reserved
    case .finite(let value):
      if axis {
        return min(child + reserved, value)
      }
      return value
    case .infinity:
      return child + reserved
    }
  }

  private func measuredContent(
    for proposal: ProposedViewSize,
    subview: LayoutSubview
  ) -> (childSize: LayoutSize, indicatorInsets: IndicatorInsets) {
    var indicatorInsets = IndicatorInsets()
    var childSize = LayoutSize.zero

    for _ in 0..<3 {
      childSize = subview.sizeThatFits(
        contentProposal(for: proposal, indicatorInsets: indicatorInsets)
      )
      let nextInsets = requiredIndicatorInsets(
        for: childSize,
        proposal: proposal,
        currentInsets: indicatorInsets
      )
      if nextInsets == indicatorInsets {
        return (childSize, indicatorInsets)
      }
      indicatorInsets = nextInsets
    }

    childSize = subview.sizeThatFits(
      contentProposal(for: proposal, indicatorInsets: indicatorInsets)
    )
    return (childSize, indicatorInsets)
  }

  private func requiredIndicatorInsets(
    for childSize: LayoutSize,
    proposal: ProposedViewSize,
    currentInsets: IndicatorInsets
  ) -> IndicatorInsets {
    guard showsIndicators else {
      return .init()
    }

    let contentViewportWidth = viewportValue(
      for: proposal.width,
      fallback: childSize.width,
      reserved: currentInsets.trailing
    )
    let contentViewportHeight = viewportValue(
      for: proposal.height,
      fallback: childSize.height,
      reserved: currentInsets.bottom
    )

    return .init(
      trailing: axes.contains(.vertical) && childSize.height > contentViewportHeight ? 1 : 0,
      bottom: axes.contains(.horizontal) && childSize.width > contentViewportWidth ? 1 : 0
    )
  }

  private func viewportValue(
    for dimension: ProposedDimension,
    fallback: Int,
    reserved: Int
  ) -> Int {
    switch dimension {
    case .unspecified, .infinity:
      return fallback
    case .finite(let value):
      return max(0, value - reserved)
    }
  }

  private func reducedDimension(
    _ dimension: ProposedDimension,
    by amount: Int
  ) -> ProposedDimension {
    switch dimension {
    case .finite(let value):
      return .finite(max(0, value - amount))
    case .unspecified, .infinity:
      return dimension
    }
  }

  private func contentViewport(
    in bounds: LayoutRect,
    indicatorInsets: IndicatorInsets
  ) -> LayoutRect {
    .init(
      origin: bounds.origin,
      size: .init(
        width: max(0, bounds.size.width - indicatorInsets.trailing),
        height: max(0, bounds.size.height - indicatorInsets.bottom)
      )
    )
  }

  private func contentOffset(
    childSize: LayoutSize,
    viewportSize: LayoutSize
  ) -> ScrollPosition {
    ScrollPosition(
      x: clampedOffset(
        requested: position.x,
        content: childSize.width,
        viewport: viewportSize.width,
        isScrollable: axes.contains(.horizontal)
      ),
      y: clampedOffset(
        requested: position.y,
        content: childSize.height,
        viewport: viewportSize.height,
        isScrollable: axes.contains(.vertical)
      )
    )
  }

  private func clampedOffset(
    requested: Int,
    content: Int,
    viewport: Int,
    isScrollable: Bool
  ) -> Int {
    guard isScrollable else {
      return 0
    }
    return min(max(0, requested), max(0, content - viewport))
  }
}

extension ScrollViewLayout {
  var measurementReuseSignature: String? {
    "ScrollViewLayout:\(axes.rawValue):\(showsIndicators)"
  }

  var placementReuseSignature: String? {
    "ScrollViewLayout:\(axes.rawValue):\(showsIndicators):\(position.x):\(position.y)"
  }
}
