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
          measured: childMeasurement,
          passContext: passContext
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
          measured: childMeasurement,
          passContext: passContext
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
    if let source = resolved.indexedChildSource,
      let allocation = measured.containerAllocationSnapshot,
      let snapshot = allocation.lazyStack
    {
      if let fragments = snapshot.fragments {
        if let viewportContext {
          let viewport = viewportContext.viewportRect
          let offset =
            axis == .vertical
            ? viewport.origin.y - bounds.origin.y
            : viewport.origin.x - bounds.origin.x
          let length = mainDimension(of: viewport.size, for: axis)
          let storedOffset =
            snapshot.correctedContentOffset
            ?? snapshot.windowHint.map { mainDimension(of: $0.contentOffset, for: axis) }
          let storedLength = snapshot.windowHint.map {
            mainDimension(of: $0.viewportSize, for: axis)
          }
          if storedOffset != offset || storedLength != length {
            let context = passContext ?? LayoutPassContext()
            var hint =
              snapshot.windowHint
              ?? .init(
                axes: viewportContext.axes,
                contentOffset: viewportContext.contentOffset, viewportSize: viewport.size)
            hint.viewportSize = viewport.size
            if axis == .vertical {
              hint.contentOffset.y = max(0, offset)
            } else {
              hint.contentOffset.x = max(0, offset)
            }
            let refined = context.withMeasureViewportHint(hint) {
              measure(resolved, proposal: measured.proposal, passContext: context)
            }
            // The entire logical band remeasures through the work stack; no
            // fragment loop re-enters measurement on the native stack.
            return lazyStackPlacementRequests(
              for: resolved, measured: refined, in: bounds,
              axis: axis, spacing: spacing, horizontalAlignment: horizontalAlignment,
              verticalAlignment: verticalAlignment, viewportContext: nil, passContext: context
            )
            .filter { request in
              let start = mainDimension(of: request.bounds.origin, for: axis)
              let end = start + mainDimension(of: request.bounds.size, for: axis)
              let visibleStart = mainDimension(of: viewport.origin, for: axis)
              return end > visibleStart && start < visibleStart + length
            }
          }
        }
        return fragments.compactMap { fragment in
          if let viewportContext {
            let start = mainDimension(of: bounds.origin, for: axis) + fragment.mainOffset
            let end = start + mainDimension(of: fragment.measurement.measuredSize, for: axis)
            let visibleStart = mainDimension(of: viewportContext.viewportRect.origin, for: axis)
            let visibleEnd =
              visibleStart + mainDimension(of: viewportContext.viewportRect.size, for: axis)
            if end <= visibleStart || start >= visibleEnd { return nil }
          }
          let children = source.childElements(at: fragment.elementIndex)
          guard children.indices.contains(fragment.fragmentIndex) else { return nil }
          let child = children[fragment.fragmentIndex]
          let dimensions = viewDimensions(
            for: child, measured: fragment.measurement,
            passContext: passContext)
          let origin =
            axis == .vertical
            ? CellPoint(
              x: bounds.origin.x + snapshot.crossLeading - dimensions[horizontalAlignment],
              y: bounds.origin.y + fragment.mainOffset)
            : CellPoint(
              x: bounds.origin.x + fragment.mainOffset,
              y: bounds.origin.y + snapshot.crossLeading - dimensions[verticalAlignment])
          return PlacementRequest(
            resolved: child, measured: fragment.measurement,
            bounds: CellRect(origin: origin, size: fragment.measurement.measuredSize))
        }
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
        verticalAlignment: verticalAlignment,
        passContext: passContext
      )
    }

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
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement,
          passContext: passContext
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
          measured: childMeasurement,
          passContext: passContext
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
    childAt: (Int) -> ResolvedNode,
    childSizes: [ChildAllocation],
    measured: MeasuredNode,
    in bounds: CellRect,
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    snapshot: LazyStackAllocationSnapshot,
    visibleRange: Range<Int>,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    visibleRange.map { index in
      let child = childAt(index)
      let size = childSizes[index].size
      var measurement = measure(
        child,
        proposal: stackProposal(
          axis: axis,
          main: .finite(mainDimension(of: size, for: axis)),
          cross: crossDimension(of: measured.proposal, for: axis)), passContext: passContext)
      if isSpacer(child) {
        measurement.measuredSize = settingMainDimension(
          of: measurement.measuredSize,
          for: axis, to: mainDimension(of: size, for: axis))
      }
      let dimensions = viewDimensions(for: child, measured: measurement, passContext: passContext)
      let origin =
        axis == .vertical
        ? CellPoint(
          x: bounds.origin.x + snapshot.crossLeading - dimensions[horizontalAlignment],
          y: bounds.origin.y + snapshot.childMainOffsets[index])
        : CellPoint(
          x: bounds.origin.x + snapshot.childMainOffsets[index],
          y: bounds.origin.y + snapshot.crossLeading - dimensions[verticalAlignment])
      return PlacementRequest(
        resolved: child, measured: measurement,
        bounds: CellRect(origin: origin, size: measurement.measuredSize))
    }
  }
}
