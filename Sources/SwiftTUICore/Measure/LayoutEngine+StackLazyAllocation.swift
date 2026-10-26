extension LayoutEngine {
  package func stackChildren(
    for resolved: ResolvedNode
  ) -> [ResolvedNode] {
    // Hosted List/Table sources have their own viewport allocation snapshot.
    // Treating them as generic indexed stacks here realizes the entire source
    // during enclosing-stack flexibility/minimum-size derivation, even though
    // their measurement already contains only the visible window.
    if resolved.semanticMetadata.hostedCollectionContainer != nil {
      return resolved.children
    }
    guard let source = resolved.indexedChildSource else {
      return resolved.children
    }

    if resolved.children.count == source.count {
      return resolved.children
    }

    return (0..<source.count).flatMap { source.childElements(at: $0) }
  }

  package func lazyStackAllocationSnapshot(
    for children: [ResolvedNode],
    childMeasurements: [MeasuredNode],
    axis: Axis,
    spacingOverride: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment
  ) -> LazyStackAllocationSnapshot {
    let stackSpacings = resolvedStackSpacings(
      for: children,
      axis: axis,
      spacingOverride: spacingOverride
    )
    let crossMetrics = stackCrossMetrics(
      for: children,
      childMeasurements: childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    var childMainOffsets: [Int] = []
    var childMainLengths: [Int] = []
    childMainOffsets.reserveCapacity(childMeasurements.count)
    childMainLengths.reserveCapacity(childMeasurements.count)

    var nextOffset = 0
    for (index, measurement) in childMeasurements.enumerated() {
      let length = mainDimension(of: measurement.measuredSize, for: axis)
      childMainOffsets.append(nextOffset)
      childMainLengths.append(length)
      nextOffset = SaturatingConversion.adding(nextOffset, length)
      if index < stackSpacings.count {
        nextOffset = SaturatingConversion.adding(nextOffset, stackSpacings[index])
      }
    }

    return LazyStackAllocationSnapshot(
      axis: axis,
      childMainOffsets: childMainOffsets,
      childMainLengths: childMainLengths,
      childIdentities: children.map(\.identity),
      contentMainLength: nextOffset,
      crossLeading: crossMetrics.leading,
      crossTrailing: crossMetrics.trailing,
      crossLineIsHalfCell: crossMetrics.isHalfCell
    )
  }

  /// The children of a lazy stack that intersect the scroll viewport, widened
  /// by `overscan`.
  ///
  /// `nil` means the viewport does not window this stack — it scrolls the
  /// other axis, it has no main-axis length, or the stack has no content —
  /// and the caller places every child. An empty range means the viewport
  /// applies and no child intersects it: the stack lies wholly outside the
  /// viewport (or the visible band falls between children), so it realizes no
  /// rows, exactly as the windowed fragment path does. Conflating the two let
  /// a wholly offscreen exhaustive stack place every row while the same stack
  /// one row higher placed only its visible ones (STUI-1231).
  package func lazyStackVisibleChildRange(
    for snapshot: LazyStackAllocationSnapshot,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext,
    overscan: Int = 1
  ) -> Range<Int>? {
    let axisMatches =
      switch snapshot.axis {
      case .horizontal:
        viewportContext.axes.contains(.horizontal)
      case .vertical:
        viewportContext.axes.contains(.vertical)
      }
    guard axisMatches else {
      return nil
    }

    let viewportLength =
      mainDimension(of: viewportContext.viewportRect.size, for: snapshot.axis)
    let childCount = min(snapshot.childMainOffsets.count, snapshot.childMainLengths.count)
    guard viewportLength > 0, snapshot.contentMainLength > 0, childCount > 0 else {
      return nil
    }

    // Absolute intersection: the stack's placement bounds are already
    // scroll-translated (the scroll layout places its content at
    // viewport origin minus the clamped offset), and the viewport rect is
    // absolute, so intersecting the two main-axis ranges yields the visible
    // band for a stack ANYWHERE inside the scrolled content — a header
    // above the stack or wrapper nesting shifts `bounds`, not this math.
    // The previous form read `contentOffset` directly, which is the stack's
    // own scroll position only when the stack IS the content origin.
    let stackStart = mainDimension(of: bounds.origin, for: snapshot.axis)
    let viewportStart =
      mainDimension(of: viewportContext.viewportRect.origin, for: snapshot.axis)
    let visibleStart = max(
      0,
      min(
        SaturatingConversion.subtracting(viewportStart, stackStart),
        snapshot.contentMainLength)
    )
    let visibleEnd = min(
      snapshot.contentMainLength,
      SaturatingConversion.subtracting(
        SaturatingConversion.adding(viewportStart, viewportLength), stackStart)
    )
    guard visibleStart < visibleEnd else {
      return 0..<0
    }

    // Overlapping layouts need exact interval traversal. Binary search is
    // invalid when either starts or ends are nonmonotone.
    if (1..<childCount).contains(where: {
      snapshot.childMainOffsets[$0]
        < SaturatingConversion.adding(
          snapshot.childMainOffsets[$0 - 1], snapshot.childMainLengths[$0 - 1])
    }) {
      return 0..<childCount
    }

    let firstVisible = firstLazyStackChildIndex(
      in: snapshot,
      lowerBoundOfChildEndAfter: visibleStart,
      childCount: childCount
    )
    let lastVisibleExclusive = firstLazyStackChildIndex(
      in: snapshot,
      lowerBoundOfChildStartAtOrAfter: visibleEnd,
      childCount: childCount
    )

    // A band between two children intersects none; overscan may still
    // realize its neighbours.
    let overscannedLower = max(0, firstVisible - max(0, overscan))
    let overscannedUpper = min(childCount, lastVisibleExclusive + max(0, overscan))
    guard overscannedLower < overscannedUpper else {
      return 0..<0
    }

    return overscannedLower..<overscannedUpper
  }

  private func firstLazyStackChildIndex(
    in snapshot: LazyStackAllocationSnapshot,
    lowerBoundOfChildEndAfter target: Int,
    childCount: Int
  ) -> Int {
    var lower = 0
    var upper = childCount

    while lower < upper {
      let mid = (lower + upper) / 2
      let childEnd = SaturatingConversion.adding(
        snapshot.childMainOffsets[mid], snapshot.childMainLengths[mid])
      if childEnd <= target {
        lower = mid + 1
      } else {
        upper = mid
      }
    }

    return lower
  }

  private func firstLazyStackChildIndex(
    in snapshot: LazyStackAllocationSnapshot,
    lowerBoundOfChildStartAtOrAfter target: Int,
    childCount: Int
  ) -> Int {
    var lower = 0
    var upper = childCount

    while lower < upper {
      let mid = (lower + upper) / 2
      if snapshot.childMainOffsets[mid] < target {
        lower = mid + 1
      } else {
        upper = mid
      }
    }

    return lower
  }
}
