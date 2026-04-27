extension LayoutEngine {
  package func childPlacements(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    switch resolved.layoutBehavior {
    case .intrinsic:
      let childCount = min(resolved.children.count, measured.childMeasurements.count)
      var placements: [PlacedNode] = []
      placements.reserveCapacity(childCount)
      for index in 0..<childCount {
        let childMeasurement = measured.childMeasurements[index]
        placements.append(
          place(
            resolved.children[index],
            measured: childMeasurement,
            in: Rect(origin: bounds.origin, size: childMeasurement.measuredSize),
            passContext: passContext
          )
        )
      }
      return placements
    case .overlay(let alignment):
      let alignmentMetrics = overlayAlignmentMetrics(
        for: resolved.children,
        childMeasurements: measured.childMeasurements,
        alignment: alignment
      )
      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        let childDimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: bounds.origin.x + alignmentMetrics.leading - childDimensions[alignment.horizontal],
              y: bounds.origin.y + alignmentMetrics.top - childDimensions[alignment.vertical]
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      return placeStackChildren(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .vertical,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center,
        passContext: passContext
      )
    case .stack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      return placeStackChildren(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .horizontal,
        spacing: spacing,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment,
        passContext: passContext
      )
    case .lazyStack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      return placeLazyStackChildren(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .vertical,
        spacing: spacing,
        horizontalAlignment: horizontalAlignment,
        verticalAlignment: .center,
        viewportContext: viewportContext,
        passContext: passContext
      )
    case .lazyStack(
      axis: .horizontal, let spacing,
      horizontalAlignment: _, let verticalAlignment
    ):
      return placeLazyStackChildren(
        for: resolved,
        measured: measured,
        in: bounds,
        axis: .horizontal,
        spacing: spacing,
        horizontalAlignment: .center,
        verticalAlignment: verticalAlignment,
        viewportContext: viewportContext,
        passContext: passContext
      )
    case .padding(let insets):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let childBounds = Rect(
        origin: Point(
          x: bounds.origin.x + insets.leading,
          y: bounds.origin.y + insets.top
        ),
        size: Size(
          width: max(0, bounds.size.width - insets.horizontal),
          height: max(0, bounds.size.height - insets.vertical)
        )
      )

      return [
        place(
          child,
          measured: childMeasurement,
          in: childBounds,
          passContext: passContext
        )
      ]
    case .safeAreaIgnoring(let insets):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let childBounds = Rect(
        origin: Point(
          x: bounds.origin.x - insets.leading,
          y: bounds.origin.y - insets.top
        ),
        size: Size(
          width: bounds.size.width + insets.horizontal,
          height: bounds.size.height + insets.vertical
        )
      )

      return [
        place(
          child,
          measured: childMeasurement,
          in: childBounds,
          passContext: passContext
        )
      ]
    case .safeAreaInset(let edge, let alignment, let spacing, let safeArea):
      guard resolved.children.count >= 2, measured.childMeasurements.count >= 2 else {
        return measured.childMeasurements.enumerated().compactMap { index, childMeasurement in
          guard resolved.children.indices.contains(index) else { return nil }
          return place(
            resolved.children[index],
            measured: childMeasurement,
            in: Rect(origin: bounds.origin, size: childMeasurement.measuredSize),
            passContext: passContext
          )
        }
      }

      let base = resolved.children[0]
      let inset = resolved.children[1]
      let baseMeasurement = measured.childMeasurements[0]
      let insetMeasurement = measured.childMeasurements[1]
      let insetLength =
        switch edge {
        case .top, .bottom:
          insetMeasurement.measuredSize.height
        case .leading, .trailing:
          insetMeasurement.measuredSize.width
        }
      let consumed = max(0, insetLength + spacing - safeArea.value(for: edge))

      let baseBounds: Rect =
        switch edge {
        case .top:
          Rect(
            origin: Point(x: bounds.origin.x, y: bounds.origin.y + consumed),
            size: Size(width: bounds.size.width, height: max(0, bounds.size.height - consumed))
          )
        case .leading:
          Rect(
            origin: Point(x: bounds.origin.x + consumed, y: bounds.origin.y),
            size: Size(width: max(0, bounds.size.width - consumed), height: bounds.size.height)
          )
        case .bottom:
          Rect(
            origin: bounds.origin,
            size: Size(width: bounds.size.width, height: max(0, bounds.size.height - consumed))
          )
        case .trailing:
          Rect(
            origin: bounds.origin,
            size: Size(width: max(0, bounds.size.width - consumed), height: bounds.size.height)
          )
        }

      let insetOrigin: Point =
        switch edge {
        case .top:
          Point(
            x: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.width,
              availableSize: bounds.size.width,
              origin: bounds.origin.x,
              alignment: alignment.horizontal,
              hasExplicitGuide: false
            ) ?? bounds.origin.x,
            y: bounds.origin.y - safeArea.top
          )
        case .bottom:
          Point(
            x: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.width,
              availableSize: bounds.size.width,
              origin: bounds.origin.x,
              alignment: alignment.horizontal,
              hasExplicitGuide: false
            ) ?? bounds.origin.x,
            y: bounds.maxY - insetMeasurement.measuredSize.height + safeArea.bottom
          )
        case .leading:
          Point(
            x: bounds.origin.x - safeArea.leading,
            y: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.height,
              availableSize: bounds.size.height,
              origin: bounds.origin.y,
              alignment: alignment.vertical,
              hasExplicitGuide: false
            ) ?? bounds.origin.y
          )
        case .trailing:
          Point(
            x: bounds.maxX - insetMeasurement.measuredSize.width + safeArea.trailing,
            y: simpleAlignedCoordinate(
              childSize: insetMeasurement.measuredSize.height,
              availableSize: bounds.size.height,
              origin: bounds.origin.y,
              alignment: alignment.vertical,
              hasExplicitGuide: false
            ) ?? bounds.origin.y
          )
        }

      let insetBounds = Rect(
        origin: insetOrigin,
        size: insetMeasurement.measuredSize
      )

      return [
        place(
          base,
          measured: baseMeasurement,
          in: baseBounds,
          passContext: passContext
        ),
        place(
          inset,
          measured: insetMeasurement,
          in: insetBounds,
          passContext: passContext
        ),
      ]
    case .border(let set, let placement, _, _, _, _, let sides):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let insets = borderLayoutInsets(
        set: set, placement: placement, sides: sides)
      let childBounds = Rect(
        origin: Point(
          x: bounds.origin.x + insets.leading,
          y: bounds.origin.y + insets.top
        ),
        size: Size(
          width: max(0, bounds.size.width - insets.horizontal),
          height: max(0, bounds.size.height - insets.vertical)
        )
      )

      return [
        place(
          child,
          measured: childMeasurement,
          in: childBounds,
          passContext: passContext
        )
      ]
    case .frame(_, _, let alignment), .flexibleFrame(_, _, _, _, _, _, let alignment):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      let childOrigin =
        simpleAlignedOrigin(
          for: child,
          measured: childMeasurement,
          in: bounds,
          alignment: alignment
        )
        ?? alignedOrigin(
          for: viewDimensions(for: child, measured: childMeasurement),
          in: bounds,
          alignment: alignment
        )
      return [
        place(
          child,
          measured: childMeasurement,
          in: Rect(
            origin: childOrigin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      ]
    case .offset(let x, let y):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }

      return [
        place(
          child,
          measured: childMeasurement,
          in: Rect(
            origin: .init(
              x: bounds.origin.x + x,
              y: bounds.origin.y + y
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      ]
    case .position(let x, let y):
      // Place the child centered at (bounds.origin + x, bounds.origin
      // + y).  Matches SwiftUI's `.position(x:y:)` semantics.  The
      // wrapper itself takes the full proposed bounds (see `measure`),
      // so `x`/`y` are interpreted relative to the wrapper's origin.
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        return []
      }
      let childSize = childMeasurement.measuredSize
      return [
        place(
          child,
          measured: childMeasurement,
          in: Rect(
            origin: .init(
              x: bounds.origin.x + x - childSize.width / 2,
              y: bounds.origin.y + y - childSize.height / 2
            ),
            size: childSize
          ),
          passContext: passContext
        )
      ]
    case .decoration(let primaryIndex, let alignment):
      guard
        resolved.children.indices.contains(primaryIndex),
        measured.childMeasurements.indices.contains(primaryIndex)
      else {
        return []
      }

      let primaryDimensions = viewDimensions(
        for: resolved.children[primaryIndex],
        measured: measured.childMeasurements[primaryIndex]
      )

      return measured.childMeasurements.enumerated().map { index, childMeasurement in
        let childDimensions = viewDimensions(
          for: resolved.children[index],
          measured: childMeasurement
        )
        let childOrigin = alignedOrigin(
          for: childDimensions,
          referenceDimensions: primaryDimensions,
          in: bounds,
          alignment: alignment
        )
        return place(
          resolved.children[index],
          measured: childMeasurement,
          in: Rect(
            origin: childOrigin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .viewThatFits:
      guard
        let selectedIndex = measured.containerAllocationSnapshot?.selectedChildIndex,
        measured.childMeasurements.indices.contains(selectedIndex),
        resolved.children.indices.contains(selectedIndex)
      else {
        return []
      }

      let childMeasurement = measured.childMeasurements[selectedIndex]
      return [
        place(
          resolved.children[selectedIndex],
          measured: childMeasurement,
          in: Rect(
            origin: bounds.origin,
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      ]
    case .custom(let handle):
      return handle.placeSubviews(
        engine: self,
        node: resolved,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }
  }

  private func placeStackChildren(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    let stackChildren = stackChildren(for: resolved)
    let stackSpacings = resolvedStackSpacings(
      for: stackChildren,
      axis: axis,
      spacingOverride: spacing
    )
    let crossMetrics = stackCrossMetrics(
      for: stackChildren,
      childMeasurements: measured.childMeasurements,
      axis: axis,
      horizontalAlignment: horizontalAlignment,
      verticalAlignment: verticalAlignment
    )

    switch axis {
    case .vertical:
      var nextY = bounds.origin.y
      let placements = measured.childMeasurements.enumerated().map { index, childMeasurement in
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
        return place(
          stackChildren[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: nextY
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
      return placements
    case .horizontal:
      var nextX = bounds.origin.x
      let placements = measured.childMeasurements.enumerated().map { index, childMeasurement in
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
        return place(
          stackChildren[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: nextX,
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
      return placements
    }
  }

  private func placeLazyStackChildren(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: Rect,
    axis: Axis,
    spacing: Int?,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    if let source = resolved.indexedChildSource,
      let allocation = measured.containerAllocationSnapshot,
      let snapshot = allocation.lazyStack,
      allocation.childSizes.count == source.count
    {
      let visibleRange =
        viewportContext.flatMap {
          lazyStackVisibleChildRange(
            for: snapshot,
            viewportContext: $0,
            overscan: 0
          )
        } ?? (0..<source.count)

      return placeIndexedLazyStackChildren(
        source: source,
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

    let stackChildren = stackChildren(for: resolved)
    guard let viewportContext else {
      return placeStackChildren(
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

    guard let snapshot = measured.containerAllocationSnapshot?.lazyStack else {
      return placeStackChildren(
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

    guard
      let visibleRange = lazyStackVisibleChildRange(
        for: snapshot,
        viewportContext: viewportContext
      )
    else {
      return placeStackChildren(
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
        let childOriginY =
          bounds.origin.y + snapshot.childMainOffsets[index]
        return place(
          stackChildren[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: bounds.origin.x + crossMetrics.leading - dimensions[horizontalAlignment],
              y: childOriginY
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    case .horizontal:
      return visibleRange.map { index in
        let childMeasurement = measured.childMeasurements[index]
        let dimensions = viewDimensions(
          for: stackChildren[index],
          measured: childMeasurement
        )
        let childOriginX =
          bounds.origin.x + snapshot.childMainOffsets[index]
        return place(
          stackChildren[index],
          measured: childMeasurement,
          in: Rect(
            origin: Point(
              x: childOriginX,
              y: bounds.origin.y + crossMetrics.leading - dimensions[verticalAlignment]
            ),
            size: childMeasurement.measuredSize
          ),
          passContext: passContext
        )
      }
    }
  }

  private func placeIndexedLazyStackChildren(
    source: any IndexedChildSource,
    childSizes: [ChildAllocation],
    measured: MeasuredNode,
    in bounds: Rect,
    axis: Axis,
    horizontalAlignment: HorizontalAlignment,
    verticalAlignment: VerticalAlignment,
    snapshot: LazyStackAllocationSnapshot,
    visibleRange: Range<Int>,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    visibleRange.map { index in
      let child = source.child(at: index)
      let childSize = childSizes[index].size
      var childMeasurement = measure(
        child,
        proposal: stackProposal(
          axis: axis,
          main: .finite(mainDimension(of: childSize, for: axis)),
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
      let dimensions = viewDimensions(
        for: child,
        measured: childMeasurement
      )

      let origin: Point =
        switch axis {
        case .vertical:
          .init(
            x: bounds.origin.x + snapshot.crossLeading - dimensions[horizontalAlignment],
            y: bounds.origin.y + snapshot.childMainOffsets[index]
          )
        case .horizontal:
          .init(
            x: bounds.origin.x + snapshot.childMainOffsets[index],
            y: bounds.origin.y + snapshot.crossLeading - dimensions[verticalAlignment]
          )
        }

      return place(
        child,
        measured: childMeasurement,
        in: Rect(
          origin: origin,
          size: childMeasurement.measuredSize
        ),
        passContext: passContext
      )
    }
  }

  package func placedNode(
    from resolved: ResolvedNode,
    bounds: Rect,
    measured: MeasuredNode,
    children: [PlacedNode]
  ) -> PlacedNode {
    let contentBounds = resolvedContentBounds(
      for: resolved,
      bounds: bounds,
      measured: measured,
      children: children
    )

    return PlacedNode(
      identity: resolved.identity,
      kind: resolved.kind,
      environmentSnapshot: resolved.environmentSnapshot,
      bounds: bounds,
      contentBounds: contentBounds,
      children: children,
      semanticRole: semanticRole(for: resolved),
      layoutMetadata: resolved.layoutMetadata,
      drawMetadata: resolved.drawMetadata,
      semanticMetadata: resolved.semanticMetadata,
      lifecycleMetadata: resolved.lifecycleMetadata,
      drawPayload: resolved.drawPayload,
      layoutBehavior: resolved.layoutBehavior,
      isTransient: resolved.isTransient,
      matchedGeometry: resolved.matchedGeometry
    )
  }

  package func combinedContentBounds(
    parentBounds: Rect,
    children: [PlacedNode]
  ) -> Rect {
    children.reduce(parentBounds) { partial, child in
      union(partial, child.contentBounds)
    }
  }

  package func union(
    _ lhs: Rect,
    _ rhs: Rect
  ) -> Rect {
    let minX = min(lhs.origin.x, rhs.origin.x)
    let minY = min(lhs.origin.y, rhs.origin.y)
    let maxX = max(lhs.origin.x + lhs.size.width, rhs.origin.x + rhs.size.width)
    let maxY = max(lhs.origin.y + lhs.size.height, rhs.origin.y + rhs.size.height)

    return Rect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }

  package func resolvedContentBounds(
    for resolved: ResolvedNode,
    bounds: Rect,
    measured: MeasuredNode,
    children: [PlacedNode]
  ) -> Rect {
    let childContentBounds = combinedContentBounds(
      parentBounds: bounds,
      children: children
    )

    switch resolved.drawPayload {
    case .image:
      return childContentBounds
    case .list(let payload):
      return union(
        childContentBounds,
        Rect(
          origin: bounds.origin,
          size: measuredListIdealSize(for: payload)
        )
      )
    case .table(let payload):
      return union(
        childContentBounds,
        Rect(
          origin: bounds.origin,
          size: measuredTableIdealSize(for: payload)
        )
      )
    case .none:
      break
    default:
      break
    }

    switch resolved.layoutBehavior {
    case .offset(let x, let y):
      if let child = children.first {
        return translated(
          child.contentBounds,
          by: .init(x: -x, y: -y)
        )
      }
      return bounds
    case .position:
      // `.position` reserves the full proposed bounds for its
      // absolute placement area.  The content bounds are simply
      // the wrapper's bounds — the child sits somewhere inside
      // that area, but scroll views and parents should see the
      // entire reserved region.
      return bounds
    case .lazyStack(let axis, _, _, _):
      guard
        let snapshot = measured.containerAllocationSnapshot?.lazyStack,
        snapshot.contentMainLength > 0
      else {
        return union(childContentBounds, bounds)
      }

      let contentSize: Size =
        switch axis {
        case .vertical:
          .init(
            width: snapshot.crossLeading + snapshot.crossTrailing,
            height: snapshot.contentMainLength
          )
        case .horizontal:
          .init(
            width: snapshot.contentMainLength,
            height: snapshot.crossLeading + snapshot.crossTrailing
          )
        }
      let contentBounds = Rect(origin: bounds.origin, size: contentSize)
      return union(childContentBounds, contentBounds)
    default:
      return childContentBounds
    }
  }

  package func semanticRole(for resolved: ResolvedNode) -> SemanticRole {
    if resolved.semanticMetadata.scrollRole != nil {
      return .scroll
    }
    if resolved.participatesInTopLevelFocus
      || resolved.semanticMetadata.participatesInPointerHitTesting
    {
      return .control
    }
    switch resolved.layoutBehavior {
    case .stack, .lazyStack, .overlay, .padding, .safeAreaIgnoring, .safeAreaInset, .border,
      .frame, .offset, .position, .flexibleFrame, .decoration, .viewThatFits, .custom:
      return .container
    case .intrinsic:
      return .generic
    }
  }

  package func translatedPlacement(
    _ node: PlacedNode,
    by delta: Point
  ) -> PlacedNode {
    let translatedBounds = translated(node.bounds, by: delta)
    let translatedChildren = node.children.map { child in
      translatedPlacement(child, by: delta)
    }

    return PlacedNode(
      identity: node.identity,
      kind: node.kind,
      environmentSnapshot: node.environmentSnapshot,
      bounds: translatedBounds,
      contentBounds: translated(node.contentBounds, by: delta),
      clipBounds: node.clipBounds.map { translated($0, by: delta) },
      zIndex: node.zIndex,
      children: translatedChildren,
      semanticRole: node.semanticRole,
      layoutMetadata: node.layoutMetadata,
      drawMetadata: node.drawMetadata,
      semanticMetadata: node.semanticMetadata,
      lifecycleMetadata: node.lifecycleMetadata,
      drawPayload: node.drawPayload,
      layoutBehavior: node.layoutBehavior,
      isTransient: node.isTransient,
      matchedGeometry: node.matchedGeometry
    )
  }

  private func translated(
    _ rect: Rect,
    by delta: Point
  ) -> Rect {
    Rect(
      origin: .init(
        x: rect.origin.x + delta.x,
        y: rect.origin.y + delta.y
      ),
      size: rect.size
    )
  }
}
