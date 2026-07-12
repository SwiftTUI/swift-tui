extension LayoutEngine {
  package func stackChildren(
    for resolved: ResolvedNode
  ) -> [ResolvedNode] {
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
      nextOffset += length
      if index < stackSpacings.count {
        nextOffset += stackSpacings[index]
      }
    }

    return LazyStackAllocationSnapshot(
      axis: axis,
      childMainOffsets: childMainOffsets,
      childMainLengths: childMainLengths,
      childIdentities: children.map(\.identity),
      contentMainLength: nextOffset,
      crossLeading: crossMetrics.leading,
      crossTrailing: crossMetrics.trailing
    )
  }

  package func lazyStackVisibleChildRange(
    for snapshot: LazyStackAllocationSnapshot,
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
    guard viewportLength > 0, snapshot.contentMainLength > 0 else {
      return nil
    }

    let contentOffset = max(
      0,
      mainDimension(of: viewportContext.contentOffset, for: snapshot.axis)
    )
    let visibleStart = min(contentOffset, snapshot.contentMainLength)
    let visibleEnd = min(snapshot.contentMainLength, visibleStart + viewportLength)
    guard visibleStart < visibleEnd else {
      return nil
    }

    let childCount = min(snapshot.childMainOffsets.count, snapshot.childMainLengths.count)
    guard childCount > 0 else {
      return nil
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

    guard firstVisible < lastVisibleExclusive else {
      return nil
    }

    let overscannedLower = max(0, firstVisible - max(0, overscan))
    let overscannedUpper = min(childCount, lastVisibleExclusive + max(0, overscan))
    guard overscannedLower < overscannedUpper else {
      return nil
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
      let childEnd = snapshot.childMainOffsets[mid] + snapshot.childMainLengths[mid]
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
