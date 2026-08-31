private struct IndexedLazyStackPlacementChild {
  var index: Int
  var resolved: ResolvedNode
  var measured: MeasuredNode
}

extension LayoutEngine {
  func stackPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    passContext: LayoutPassContext? = nil
  ) -> [PlacementRequest] {
    let stackChildren = stackChildren(for: resolved)
    let stackSpacings = resolvedStackSpacings(
      for: stackChildren,
      axis: axis,
      spacingOverride: spacing,
      passContext: passContext
    )
    let crossMetrics = stackCrossMetrics(
      for: stackChildren,
      childMeasurements: measured.childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment,
      passContext: passContext
    )

    switch axis {
    case .vertical:
      var nextY = bounds.origin.y
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextY += childMeasurement.measuredSize.height
          if index < stackSpacings.count {
            nextY += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: nextY
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .horizontal:
      var nextX = bounds.origin.x
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        defer {
          nextX += childMeasurement.measuredSize.width
          if index < stackSpacings.count {
            nextX += stackSpacings[index]
          }
        }
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: nextX,
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    }
  }

  func lazyStackPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    // The viewport's main-axis span relative to the stack's origin: the
    // refinement/extension loop measures real row extents against this,
    // deliberately unclamped by the snapshot's (estimated) content length —
    // when estimates over-length the content, the estimated-visible index
    // range under-covers the viewport and only real measures can prove
    // more rows fit.
    let visibleMainWindow: Range<Int>? = viewportContext.flatMap { context in
      let axisMatches =
        switch axis {
        case .horizontal: context.axes.contains(.horizontal)
        case .vertical: context.axes.contains(.vertical)
        }
      guard axisMatches else {
        return nil
      }
      let stackStart = mainDimension(of: bounds.origin, for: axis)
      let viewportStart = mainDimension(of: context.viewportRect.origin, for: axis)
      let viewportLength = mainDimension(of: context.viewportRect.size, for: axis)
      guard viewportLength > 0 else {
        return nil
      }
      let lower = viewportStart - stackStart
      return lower..<(lower + viewportLength)
    }

    if let source = resolved.indexedChildSource,
      let allocation = measured.containerAllocationSnapshot,
      let snapshot = allocation.lazyStack
    {
      if snapshot.measuredWindow != nil, allocation.childSizes.count == source.count {
        // Windowed product (Stage 2.2): 1 cell per element by construction
        // (splices fall back to exhaustive at measure), so the source count
        // IS the flattened count and rows realize on demand strictly within
        // the visible range — realizing every element here was exactly the
        // cost windowed measurement removes.
        let visibleRange =
          viewportContext.flatMap {
            lazyStackVisibleChildRange(
              for: snapshot,
              in: bounds,
              viewportContext: $0,
              overscan: 0
            )
          } ?? (0..<source.count)

        return indexedLazyStackPlacementRequests(
          childAt: { index in
            let elements = source.childElements(at: index)
            return elements.count == 1 ? elements[0] : nil
          },
          childSizes: allocation.childSizes,
          measured: measured,
          in: bounds,
          axis: axis,
          horizontalAlignment: horizontalAlignment,
          verticalAlignment: verticalAlignment,
          snapshot: snapshot,
          visibleRange: visibleRange,
          visibleMainWindow: visibleMainWindow,
          passContext: passContext
        )
      }

      // Exhaustive product: a multi-view element contributes one cell per
      // spliced child, so the allocation arrays index the flattened list —
      // verify against the realized flattened count exactly as before.
      let flattenedChildren = stackChildren(for: resolved)
      if snapshot.measuredWindow == nil, allocation.childSizes.count == flattenedChildren.count {
        let visibleRange =
          viewportContext.flatMap {
            lazyStackVisibleChildRange(
              for: snapshot,
              in: bounds,
              viewportContext: $0,
              overscan: 0
            )
          } ?? (0..<flattenedChildren.count)

        return indexedLazyStackPlacementRequests(
          childAt: { flattenedChildren[$0] },
          childSizes: allocation.childSizes,
          measured: measured,
          in: bounds,
          axis: axis,
          horizontalAlignment: horizontalAlignment,
          verticalAlignment: verticalAlignment,
          snapshot: snapshot,
          visibleRange: visibleRange,
          visibleMainWindow: visibleMainWindow,
          passContext: passContext
        )
      }

      // The allocation snapshot indexes a different flattened child count
      // than this resolve produced — the indexed-lazy fast path would place
      // against the wrong rows. Record it; the non-indexed fallback at the
      // bottom still places every realized child (never an empty placement).
      passContext?.recordPlacementChildMismatch(
        identity: resolved.identity,
        behavior: "indexedLazyStack",
        childCount: snapshot.measuredWindow != nil ? source.count : flattenedChildren.count,
        measurementCount: allocation.childSizes.count
      )
    }

    let stackChildren = stackChildren(for: resolved)
    guard let viewportContext,
      let snapshot = measured.containerAllocationSnapshot?.lazyStack,
      let visibleRange = lazyStackVisibleChildRange(
        for: snapshot,
        in: bounds,
        viewportContext: viewportContext
      )
    else {
      return stackPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: axis,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: verticalAlignment
      )
    }

    let crossMetrics = stackCrossMetrics(
      for: stackChildren,
      childMeasurements: measured.childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    switch axis {
    case .vertical:
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: bounds.origin.y + snapshot.childMainOffsets[index]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .horizontal:
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        return PlacementRequest(
          resolved: stackChildren[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + snapshot.childMainOffsets[index],
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    }
  }

  private func indexedLazyStackPlacementRequests(
    childAt: (Int) -> ResolvedNode?,
    childSizes: [ChildAllocation],
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    snapshot: LazyStackAllocationSnapshot,
    visibleRange: Range<Int>,
    visibleMainWindow: Range<Int>?,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    guard !visibleRange.isEmpty else { return [] }

    // Window refinement can make placement's estimated-visible range extend
    // beyond the band measured earlier in this frame. Re-measure that visible
    // run at its ideal main-axis size. Rows remain adjacent, but the run must
    // not anchor at its changing visible lower bound: when that boundary drops
    // an estimated row whose real height differs, every surviving row jumps.
    // Anchor inside the measured band when it overlaps the visible run, then
    // reflow in both directions from that stable exact allocation.
    // A nil child means an on-demand realization spliced (windowed
    // products pin 1 cell per element at measure time, so this is a
    // mid-frame source drift that cannot normally happen) — tolerate by
    // not placing the row rather than misaligning every later index.
    func measuredRow(at index: Int) -> IndexedLazyStackPlacementChild? {
      guard let child = childAt(index) else {
        return nil
      }
      let childSize = childSizes[index].size
      let mainProposal: ProposedDimension =
        if snapshot.measuredWindow?.contains(index) == false {
          .unspecified
        } else {
          .finite(mainDimension(of: childSize, for: axis))
        }
      var childMeasurement = measure(
        child,
        proposal: stackProposal(
          axis: axis,
          main: mainProposal,
          cross: crossDimension(of: measured.proposal, for: axis)
        ),
        passContext: passContext
      )
      if isSpacer(child) {
        childMeasurement.measuredSize = settingMainDimension(
          of: childMeasurement.measuredSize,
          for: axis,
          to: mainDimension(of: childSize, for: axis)
        )
      }
      return IndexedLazyStackPlacementChild(
        index: index,
        resolved: child,
        measured: childMeasurement
      )
    }

    var placementChildren: [IndexedLazyStackPlacementChild] = []
    placementChildren.reserveCapacity(visibleRange.count)

    for index in visibleRange {
      guard let placementChild = measuredRow(at: index) else {
        continue
      }
      placementChildren.append(placementChild)
    }

    guard !placementChildren.isEmpty else { return [] }

    let anchorIndex: Int =
      if let measuredWindow = snapshot.measuredWindow {
        max(visibleRange.lowerBound, measuredWindow.lowerBound)
          < min(visibleRange.upperBound, measuredWindow.upperBound)
          ? max(visibleRange.lowerBound, measuredWindow.lowerBound)
          : visibleRange.lowerBound
      } else {
        visibleRange.lowerBound
      }
    var refinedLengths: [Int: Int] = [:]
    refinedLengths.reserveCapacity(placementChildren.count)
    for child in placementChildren {
      refinedLengths[child.index] = mainDimension(of: child.measured.measuredSize, for: axis)
    }

    func spacing(after index: Int) -> Int {
      guard index + 1 < snapshot.childMainOffsets.count else { return 0 }
      return snapshot.childMainOffsets[index + 1]
        - snapshot.childMainOffsets[index]
        - snapshot.childMainLengths[index]
    }

    var refinedOffsets: [Int: Int] = [
      anchorIndex: snapshot.childMainOffsets[anchorIndex]
    ]
    var nextMainOffset = snapshot.childMainOffsets[anchorIndex]
    if anchorIndex + 1 < visibleRange.upperBound {
      for index in anchorIndex..<(visibleRange.upperBound - 1) {
        nextMainOffset += refinedLengths[index] ?? snapshot.childMainLengths[index]
        nextMainOffset += spacing(after: index)
        refinedOffsets[index + 1] = nextMainOffset
      }
    }
    nextMainOffset = snapshot.childMainOffsets[anchorIndex]
    if anchorIndex > visibleRange.lowerBound {
      for index in stride(
        from: anchorIndex - 1,
        through: visibleRange.lowerBound,
        by: -1
      ) {
        nextMainOffset -= refinedLengths[index] ?? snapshot.childMainLengths[index]
        nextMainOffset -= spacing(after: index)
        refinedOffsets[index] = nextMainOffset
      }
    }

    // The estimated-visible index range came from the snapshot's ESTIMATED
    // geometry; the refined (real) extents just measured can pack the run
    // shorter than those estimates, leaving viewport rows uncovered past
    // either end of the run with nothing placed into them — the bottom-edge
    // blank-region defect (org report 2026-08-03-003, findings 1–2). Extend
    // the run with on-demand realization until the refined geometry covers
    // the viewport or rows run out; extension rows measure exactly like
    // visible-range rows, so a correctly-estimated run extends by nothing.
    if let visibleMainWindow {
      let childCount = min(childSizes.count, snapshot.childMainOffsets.count)

      let lastIndex = placementChildren[placementChildren.count - 1].index
      var cursor =
        (refinedOffsets[lastIndex] ?? snapshot.childMainOffsets[lastIndex])
        + (refinedLengths[lastIndex] ?? snapshot.childMainLengths[lastIndex])
        + spacing(after: lastIndex)
      var nextIndex = lastIndex + 1
      while cursor < visibleMainWindow.upperBound, nextIndex < childCount {
        guard let placementChild = measuredRow(at: nextIndex) else {
          break
        }
        let length = mainDimension(of: placementChild.measured.measuredSize, for: axis)
        refinedLengths[nextIndex] = length
        refinedOffsets[nextIndex] = cursor
        placementChildren.append(placementChild)
        cursor += length + spacing(after: nextIndex)
        nextIndex += 1
      }

      let firstIndex = placementChildren[0].index
      var topCursor = refinedOffsets[firstIndex] ?? snapshot.childMainOffsets[firstIndex]
      var previousIndex = firstIndex - 1
      var prepended: [IndexedLazyStackPlacementChild] = []
      while topCursor > visibleMainWindow.lowerBound, previousIndex >= 0 {
        guard let placementChild = measuredRow(at: previousIndex) else {
          break
        }
        let length = mainDimension(of: placementChild.measured.measuredSize, for: axis)
        topCursor -= length + spacing(after: previousIndex)
        refinedLengths[previousIndex] = length
        refinedOffsets[previousIndex] = topCursor
        prepended.append(placementChild)
        previousIndex -= 1
      }
      if !prepended.isEmpty {
        placementChildren = prepended.reversed() + placementChildren
      }
    }

    var requests: [PlacementRequest] = []
    requests.reserveCapacity(placementChildren.count)
    for child in placementChildren {
      let dimensions = viewDimensions(
        for: child.resolved,
        measured: child.measured
      )
      let mainOffset = refinedOffsets[child.index] ?? snapshot.childMainOffsets[child.index]

      let origin: CellPoint =
        switch axis {
        case .vertical:
          .init(
            x: bounds.origin.x + snapshot.crossLeading - dimensions[horizontalAlignment],
            y: bounds.origin.y + mainOffset
          )
        case .horizontal:
          .init(
            x: bounds.origin.x + mainOffset,
            y: bounds.origin.y + snapshot.crossLeading - dimensions[verticalAlignment]
          )
        }

      requests.append(
        PlacementRequest(
          resolved: child.resolved,
          measured: child.measured,
          bounds: CellRect(origin: origin, size: child.measured.measuredSize)
        )
      )
    }

    return requests
  }
}
