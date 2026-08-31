@_spi(Testing) import SwiftTUIPrimitives

extension LayoutEngine {
  func placementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    viewportContext: LazyStackViewportContext?,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    if let boundary = resolved.layoutRealizedContent {
      return layoutRealizedPlacementRequests(
        boundary,
        measured: measured,
        in: bounds,
        passContext: passContext
      )
    }

    switch resolved.layoutBehavior {
    case .intrinsic:
      if let hostedCollection = resolved.semanticMetadata.hostedCollectionContainer {
        switch hostedCollection.kind {
        case .list:
          if case .list(let payload) = resolved.drawPayload {
            return hostedListPlacementRequests(
              for: resolved,
              measured: measured,
              payload: payload,
              in: bounds,
              passContext: passContext
            )
          }
        case .table:
          if case .table(let payload) = resolved.drawPayload {
            return hostedTablePlacementRequests(
              for: resolved,
              measured: measured,
              payload: payload,
              in: bounds,
              passContext: passContext
            )
          }
        }
      }
      let childCount = min(resolved.children.count, measured.childMeasurements.count)
      if resolved.children.count != measured.childMeasurements.count {
        passContext?.recordPlacementChildMismatch(
          identity: resolved.identity,
          behavior: "intrinsic",
          childCount: resolved.children.count,
          measurementCount: measured.childMeasurements.count
        )
      }
      return (0..<childCount).map { index in
        let childMeasurement = measured.childMeasurements[index]
        return PlacementRequest(
          resolved: resolved.children[index],
          measured: childMeasurement,
          bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
        )
      }
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
        return PlacementRequest(
          resolved: resolved.children[index],
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + alignmentMetrics.leading - childDimensions[alignment.horizontal],
              y: bounds.origin.y + alignmentMetrics.top - childDimensions[alignment.vertical]
            ),
            size: childMeasurement.measuredSize
          )
        )
      }
    case .stack(
      axis: .vertical, let spacing, let horizontalAlignment,
      verticalAlignment: _
    ):
      return stackPlacementRequests(
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
      return stackPlacementRequests(
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
      return lazyStackPlacementRequests(
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
      return lazyStackPlacementRequests(
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
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "padding",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + insets.leading,
              y: bounds.origin.y + insets.top
            ),
            size: CellSize(
              width: max(0, bounds.size.width - insets.horizontal),
              height: max(0, bounds.size.height - insets.vertical)
            )
          )
        )
      ]
    case .safeAreaIgnoring(let insets, _):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "safeAreaIgnoring",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x - insets.leading,
              y: bounds.origin.y - insets.top
            ),
            size: CellSize(
              width: bounds.size.width + insets.horizontal,
              height: bounds.size.height + insets.vertical
            )
          )
        )
      ]
    case .safeAreaInset(let edge, let alignment, let spacing, let safeArea):
      return safeAreaInsetPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        edge: edge,
        alignment: alignment,
        spacing: spacing,
        safeArea: safeArea
      )
    case .border(let set, let placement, _, _, _, _, let sides):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "border",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      let insets = borderLayoutInsets(
        set: set,
        placement: placement,
        sides: sides
      )
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: CellPoint(
              x: bounds.origin.x + insets.leading,
              y: bounds.origin.y + insets.top
            ),
            size: CellSize(
              width: max(0, bounds.size.width - insets.horizontal),
              height: max(0, bounds.size.height - insets.vertical)
            )
          )
        )
      ]
    case .frame(_, _, let alignment), .flexibleFrame(_, _, _, _, _, _, let alignment):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "frame",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      let childOrigin =
        if resolved.kind == .view("HostedTableCell"),
          childMeasurement.measuredSize.width > bounds.size.width
        {
          bounds.origin
        } else {
          simpleAlignedOrigin(
            for: child,
            measured: childMeasurement,
            in: bounds,
            alignment: alignment,
            passContext: passContext
          )
            ?? alignedOrigin(
              for: viewDimensions(
                for: child, measured: childMeasurement, passContext: passContext),
              in: bounds,
              alignment: alignment
            )
        }
      let childSize =
        if resolved.kind == .view("HostedTableCell") {
          CellSize(width: bounds.size.width, height: childMeasurement.measuredSize.height)
        } else {
          childMeasurement.measuredSize
        }
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(origin: childOrigin, size: childSize)
        )
      ]
    case .offset(let x, let y):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "offset",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: .init(
              x: bounds.origin.x + x,
              y: bounds.origin.y + y
            ),
            size: childMeasurement.measuredSize
          )
        )
      ]
    case .position(let x, let y):
      guard let childMeasurement = measured.childMeasurements.first,
        let child = resolved.children.first
      else {
        if resolved.children.isEmpty != measured.childMeasurements.isEmpty {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "position",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }
      let childSize = childMeasurement.measuredSize
      return [
        .init(
          resolved: child,
          measured: childMeasurement,
          bounds: CellRect(
            origin: .init(
              x: bounds.origin.x + x - childSize.width / 2,
              y: bounds.origin.y + y - childSize.height / 2
            ),
            size: childSize
          )
        )
      ]
    case .decoration(let primaryIndex, let alignment):
      return decorationPlacementRequests(
        for: resolved,
        measured: measured,
        in: bounds,
        primaryIndex: primaryIndex,
        alignment: alignment,
        passContext: passContext
      )
    case .viewThatFits:
      guard
        let selectedIndex = measured.containerAllocationSnapshot?.selectedChildIndex,
        measured.childMeasurements.indices.contains(selectedIndex),
        resolved.children.indices.contains(selectedIndex)
      else {
        // A recorded selection that indexes outside either list is a
        // resolve/measure divergence — the chosen child silently vanishes.
        // No selection at all (empty ViewThatFits) is legitimate.
        if let selectedIndex = measured.containerAllocationSnapshot?.selectedChildIndex,
          !measured.childMeasurements.indices.contains(selectedIndex)
            || !resolved.children.indices.contains(selectedIndex)
        {
          passContext?.recordPlacementChildMismatch(
            identity: resolved.identity,
            behavior: "viewThatFits(selected: \(selectedIndex))",
            childCount: resolved.children.count,
            measurementCount: measured.childMeasurements.count
          )
        }
        return []
      }

      let childMeasurement = measured.childMeasurements[selectedIndex]
      return [
        .init(
          resolved: resolved.children[selectedIndex],
          measured: childMeasurement,
          bounds: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize)
        )
      ]
    case .custom:
      return []
    }
  }

  private func hostedListPlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    payload: ListPayload,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    let indexedSource = resolved.indexedChildSource
    let sourceIndices = measured.containerAllocationSnapshot?.hostedCollection?.sourceIndices ?? []
    let childCount =
      indexedSource == nil
      ? min(resolved.children.count, measured.childMeasurements.count)
      : min(sourceIndices.count, measured.childMeasurements.count)
    if indexedSource == nil, resolved.children.count != measured.childMeasurements.count {
      passContext?.recordPlacementChildMismatch(
        identity: resolved.identity,
        behavior: "hostedList",
        childCount: resolved.children.count,
        measurementCount: measured.childMeasurements.count
      )
    }

    // The measured product, translated — not a fresh derivation. Recomputing
    // here is the fallback for a parent that stretched the collection past the
    // size it was measured at, where the measured line set no longer covers
    // the bounds.
    let layout = hostedListVisibleLayout(
      for: resolved,
      measured: measured,
      payload: payload,
      in: bounds
    )
    var requests: [PlacementRequest] = []
    var placedItemIndices: Set<Int> = []
    for line in layout.lines {
      guard let itemIndex = line.itemIndex,
        placedItemIndices.insert(itemIndex).inserted
      else {
        continue
      }

      let measurementIndex: Int
      let child: ResolvedNode
      if let indexedSource {
        guard let index = sourceIndices.firstIndex(of: itemIndex), index < childCount else {
          continue
        }
        measurementIndex = index
        child = indexedSource.child(at: itemIndex)
      } else {
        guard itemIndex < childCount else {
          continue
        }
        measurementIndex = itemIndex
        child = resolved.children[itemIndex]
      }
      let childMeasurement = measured.childMeasurements[measurementIndex]
      let markerWidth = line.rowIndex == nil || !payload.showsSelectionMarker ? 0 : 2
      let origin = CellPoint(
        x: layout.contentBounds.origin.x + markerWidth,
        y: layout.contentBounds.origin.y + line.yOffset
      )
      let childBounds = CellRect(origin: origin, size: childMeasurement.measuredSize)
      let collectionBottom = bounds.origin.y + bounds.size.height
      if childBounds.origin.y < collectionBottom,
        childBounds.origin.y + childBounds.size.height > bounds.origin.y
      {
        requests.append(
          PlacementRequest(
            resolved: child,
            measured: childMeasurement,
            bounds: childBounds
          )
        )
      }
    }
    return requests
  }

  private func hostedTablePlacementRequests(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    payload: TablePayload,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacementRequest] {
    let indexedSource = resolved.indexedChildSource
    let sourceIndices = measured.containerAllocationSnapshot?.hostedCollection?.sourceIndices ?? []
    let childCount =
      indexedSource == nil
      ? min(resolved.children.count, measured.childMeasurements.count)
      : min(sourceIndices.count, measured.childMeasurements.count)
    if indexedSource == nil, resolved.children.count != measured.childMeasurements.count {
      passContext?.recordPlacementChildMismatch(
        identity: resolved.identity,
        behavior: "hostedTable",
        childCount: resolved.children.count,
        measurementCount: measured.childMeasurements.count
      )
    }

    // The measured product, translated — not a fresh derivation. Recomputing
    // here is the fallback for a parent that stretched the collection past the
    // size it was measured at, where the measured line set no longer covers
    // the bounds.
    let layout = hostedTableVisibleLayout(
      measured: measured,
      payload: payload,
      in: bounds
    )
    let leftWidth = layoutText(
      for: payload.style.borderGlyphs.left,
      width: nil
    ).size.width
    var requests: [PlacementRequest] = []
    for line in layout.lines {
      guard line.role == .row,
        let rowIndex = line.rowIndex
      else {
        continue
      }
      let measurementIndex: Int
      let child: ResolvedNode
      if let indexedSource {
        guard let index = sourceIndices.firstIndex(of: rowIndex), index < childCount else {
          continue
        }
        measurementIndex = index
        child = indexedSource.child(at: rowIndex)
      } else {
        guard rowIndex < childCount else {
          continue
        }
        measurementIndex = rowIndex
        child = resolved.children[rowIndex]
      }
      let childMeasurement = measured.childMeasurements[measurementIndex]
      let childBounds = CellRect(
        origin: .init(
          x: layout.contentBounds.origin.x + leftWidth + 1,
          y: layout.contentBounds.origin.y + line.yOffset
        ),
        size: childMeasurement.measuredSize
      )
      let collectionBottom = bounds.origin.y + bounds.size.height
      if childBounds.origin.y < collectionBottom,
        childBounds.origin.y + childBounds.size.height > bounds.origin.y
      {
        requests.append(
          PlacementRequest(
            resolved: child,
            measured: childMeasurement,
            bounds: childBounds
          )
        )
      }
    }
    return requests
  }

  /// The visible layout to place a hosted List against: the measured product
  /// translated into `bounds`, or a fresh derivation when no measured product
  /// covers these bounds (a payload-only caller, or a parent that stretched
  /// the collection past its measured size).
  func hostedListVisibleLayout(
    for resolved: ResolvedNode,
    measured: MeasuredNode,
    payload: ListPayload,
    in bounds: CellRect
  ) -> ListVisibleLayout {
    guard
      let stored = measured.containerAllocationSnapshot?.hostedCollection?.listLayout,
      stored.contentBounds.size.height
        >= listVisibleLayoutHeightRequirement(
          for: payload,
          in: bounds
        )
    else {
      return payload.style.visibleListLayout(for: payload, in: bounds)
    }
    return stored.translated(by: bounds.origin)
  }

  private func listVisibleLayoutHeightRequirement(
    for payload: ListPayload,
    in bounds: CellRect
  ) -> Int {
    payload.style.listContentHeight(in: bounds)
  }

  /// The visible layout to place a hosted Table against, on the same terms as
  /// ``hostedListVisibleLayout(for:measured:payload:in:)``.
  ///
  /// A table's layout covers its whole bounds rather than an inset sub-rect,
  /// so the "does the measured product still cover these bounds" test is a
  /// plain size comparison: a table's line widths are baked from the column
  /// widths, so a parent that stretched either axis invalidates the product.
  func hostedTableVisibleLayout(
    measured: MeasuredNode,
    payload: TablePayload,
    in bounds: CellRect
  ) -> TableVisibleLayout {
    guard
      let stored = measured.containerAllocationSnapshot?.hostedCollection?.tableLayout,
      stored.contentBounds.size == bounds.size
    else {
      return DrawExtractor().visibleTableLayout(
        for: payload,
        in: bounds,
        columnWidths: measured.containerAllocationSnapshot?.hostedCollection?.tableColumnWidths
      )
    }
    return stored.translated(by: bounds.origin)
  }
}
