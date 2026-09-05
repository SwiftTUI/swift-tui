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
// `IndicatorInsets` is file-internal too (it was `private` until the R1.3
// inset seed): a `private` stored property would demote the memberwise
// initializer below what `ScrollView.swift` needs. Nothing outside this
// layout reads it.

struct ScrollViewLayout: Layout, StackMinimumLayoutProviding {
  struct IndicatorInsets: Equatable {
    var trailing: Int = 0
    var bottom: Int = 0
  }

  var axes: Axis.Set
  var position: ScrollCellOffset
  var indicatorAxes: Axis.Set
  var contentInsets: EdgeInsets = .zero
  var reservesIndicatorSpace: Bool = true
  /// The previous frame's converged indicator insets, derived from the
  /// retained container measurement (scroll-latency R1.3). Optimization seed
  /// only: `measuredContent` verifies it with a real measurement and falls
  /// back to the cold-start loop when it does not confirm. `nil` (the
  /// default, so `ScrollView`'s memberwise construction is unchanged) means
  /// cold start.
  var indicatorInsetSeed: IndicatorInsets? = nil
  func makeCache(subviews _: LayoutSubviews) {}

  func stackMinimumMainSize(
    axis: SwiftTUICore.Axis,
    idealSize: LayoutSize,
    contentMinimum: Int
  ) -> Int? {
    // The scrolling axis is fully compressible. The non-scrolling axis
    // reports the content's structural minimum, NOT the ideal: the ideal was
    // measured with the scrolling axis unconstrained, and an `HStack`'s
    // ideal round proposes `.unspecified` on the other axis too — so text
    // content measures unwrapped there, and republishing that width as a
    // hard minimum made the pane rigid at the unwrapped ideal (min == max
    // for non-flexible subtrees), overflowing any ancestor pane. A `Text`
    // keeps its zero horizontal structural minimum whether or not a
    // vertical scroll view wraps it.
    switch axis {
    case .horizontal:
      return axes.contains(.horizontal) ? nil : contentMinimum + contentInsets.horizontal
    case .vertical:
      return axes.contains(.vertical) ? nil : contentMinimum + contentInsets.vertical
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
        reserved: indicatorInsets.trailing + contentInsets.horizontal
      ),
      height: viewportDimension(
        childSize.height,
        proposal: proposal.height,
        scrollsAlong: axes.contains(.vertical),
        reserved: indicatorInsets.bottom + contentInsets.vertical
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
        : reducedDimension(proposal.width, by: indicatorInsets.trailing + contentInsets.horizontal),
      height: axes.contains(.vertical)
        ? .unspecified
        : reducedDimension(proposal.height, by: indicatorInsets.bottom + contentInsets.vertical)
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
    // Seeded fast path (scroll-latency R1.3): start from the previous frame's
    // converged insets and verify them with ONE measurement. A confirmed seed
    // collapses the steady scroll state (indicators shown) to a single
    // content measure instead of the loop's two; a refuted seed falls through
    // to the cold-start loop UNCHANGED, so a wrong or stale seed costs one
    // extra measurement and cannot change what the loop computes from
    // scratch. Knife-edge content whose overflow flips when the indicator
    // column is reserved is bistable under the loop's own iteration order;
    // a confirmed seed keeps the previous frame's stable state instead of
    // re-deciding it, which is the hysteresis a scrollbar gutter wants —
    // without it the indicator could flicker frame to frame.
    if let seed = indicatorInsetSeed, seed != IndicatorInsets() {
      let childSize = subview.sizeThatFits(
        contentProposal(for: proposal, indicatorInsets: seed),
        measureViewport: measureViewportHint(for: proposal, indicatorInsets: seed)
      )
      let confirmedInsets = requiredIndicatorInsets(
        for: childSize,
        proposal: proposal,
        currentInsets: seed
      )
      if confirmedInsets == seed {
        return (childSize, seed)
      }
    }

    var indicatorInsets = IndicatorInsets()
    var childSize = LayoutSize.zero

    for _ in 0..<3 {
      childSize = subview.sizeThatFits(
        contentProposal(for: proposal, indicatorInsets: indicatorInsets),
        measureViewport: measureViewportHint(for: proposal, indicatorInsets: indicatorInsets)
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
      contentProposal(for: proposal, indicatorInsets: indicatorInsets),
      measureViewport: measureViewportHint(for: proposal, indicatorInsets: indicatorInsets)
    )
    return (childSize, indicatorInsets)
  }

  /// The measure-time viewport this scroll layout declares for its content
  /// (Stage 2.2): the requested offset is passed unclamped (clamping needs
  /// the content size, which is what the measurement computes — the window
  /// math clamps to the content range itself), and a dimension the proposal
  /// leaves unbounded is 0, meaning "unknown — do not window this axis".
  private func measureViewportHint(
    for proposal: ProposedViewSize,
    indicatorInsets: IndicatorInsets
  ) -> MeasureViewportHint? {
    let width: Int =
      switch proposal.width {
      case .finite(let value): max(0, value - indicatorInsets.trailing - contentInsets.horizontal)
      case .unspecified, .infinity: 0
      }
    let height: Int =
      switch proposal.height {
      case .finite(let value): max(0, value - indicatorInsets.bottom - contentInsets.vertical)
      case .unspecified, .infinity: 0
      }
    guard width > 0 || height > 0 else {
      return nil
    }
    return MeasureViewportHint(
      axes: axes,
      contentOffset: .init(x: max(0, position.x), y: max(0, position.y)),
      viewportSize: .init(width: width, height: height)
    )
  }

  private func requiredIndicatorInsets(
    for childSize: LayoutSize,
    proposal: ProposedViewSize,
    currentInsets: IndicatorInsets
  ) -> IndicatorInsets {
    guard reservesIndicatorSpace, !indicatorAxes.isEmpty else {
      return .init()
    }

    let contentViewportWidth = viewportValue(
      for: proposal.width,
      fallback: childSize.width,
      reserved: currentInsets.trailing + contentInsets.horizontal
    )
    let contentViewportHeight = viewportValue(
      for: proposal.height,
      fallback: childSize.height,
      reserved: currentInsets.bottom + contentInsets.vertical
    )

    return .init(
      trailing: indicatorAxes.contains(.vertical) && childSize.height > contentViewportHeight
        ? 1 : 0,
      bottom: indicatorAxes.contains(.horizontal) && childSize.width > contentViewportWidth
        ? 1 : 0
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
      origin: .init(
        x: bounds.origin.x + contentInsets.leading, y: bounds.origin.y + contentInsets.top),
      size: .init(
        width: max(0, bounds.size.width - indicatorInsets.trailing - contentInsets.horizontal),
        height: max(0, bounds.size.height - indicatorInsets.bottom - contentInsets.vertical)
      )
    )
  }

  private func contentOffset(
    childSize: LayoutSize,
    viewportSize: LayoutSize
  ) -> ScrollCellOffset {
    ScrollCellOffset(
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

extension ScrollViewLayout: MeasureViewportDeclaringLayout {
  /// Indicator insets are unknown before the content measures; declaring the
  /// uninset viewport makes the estimated window at most one row generous.
  func declaredMeasureViewport(for proposal: ProposedViewSize) -> MeasureViewportHint? {
    measureViewportHint(for: proposal, indicatorInsets: .init())
  }
}

extension ScrollViewLayout: RetainedMeasurementSeedableLayout {
  /// Derives the indicator-inset seed from the retained (previous-frame)
  /// content measurement — arithmetically, with no measurement of its own.
  /// In the steady scroll state the retained child size IS this frame's
  /// child size, so the solved fixed point is this frame's converged insets;
  /// a stale size yields at worst a wrong seed, which the verification
  /// measure in `measuredContent` refutes.
  mutating func applyRetainedMeasurementSeed(
    previousProposal: ProposedViewSize,
    previousChildSize: LayoutSize
  ) {
    var insets = IndicatorInsets()
    for _ in 0..<3 {
      let next = requiredIndicatorInsets(
        for: previousChildSize,
        proposal: previousProposal,
        currentInsets: insets
      )
      if next == insets {
        break
      }
      insets = next
    }
    indicatorInsetSeed = insets
  }
}

extension ScrollViewLayout {
  private var reuseSignature: String {
    "ScrollViewLayout:\(axes.rawValue):\(indicatorAxes.rawValue):\(contentInsets.top):\(contentInsets.leading):\(contentInsets.bottom):\(contentInsets.trailing):\(reservesIndicatorSpace)"
  }

  var measurementReuseSignature: String? { reuseSignature }

  var placementReuseSignature: String? {
    "\(reuseSignature):\(position.x):\(position.y)"
  }
}
