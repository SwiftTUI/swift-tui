extension SemanticExtractor {
  func appendPayloadSemantics(
    for node: PlacedNode,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    modalFocusScopePath: [Identity]?,
    clippedTo clipRect: CellRect?,
    sealingParentOnChain: Bool,
    interactionRegions: inout [InteractionRegion],
    focusRegions: inout [FocusRegion],
    nextHitTestOrder: inout Int
  ) {
    switch node.drawPayload {
    case .textFigure:
      break
    case .richText(let payload):
      appendRichTextSemantics(
        for: node,
        payload: payload,
        scopePath: scopePath,
        sectionIdentity: sectionIdentity,
        modalFocusScopePath: modalFocusScopePath,
        clippedTo: clipRect,
        sealingParentOnChain: sealingParentOnChain,
        interactionRegions: &interactionRegions,
        focusRegions: &focusRegions,
        nextHitTestOrder: &nextHitTestOrder
      )
    case .list(let payload):
      appendListSemantics(
        for: node,
        payload: payload,
        scopePath: scopePath,
        sectionIdentity: sectionIdentity,
        modalFocusScopePath: modalFocusScopePath,
        clippedTo: clipRect,
        sealingParentOnChain: sealingParentOnChain,
        interactionRegions: &interactionRegions,
        focusRegions: &focusRegions,
        nextHitTestOrder: &nextHitTestOrder
      )
    case .table(let payload):
      appendTableSemantics(
        for: node,
        payload: payload,
        clippedTo: clipRect,
        interactionRegions: &interactionRegions,
        nextHitTestOrder: &nextHitTestOrder
      )
    case .none, .rule, .shape, .text, .image, .canvas, .foreignSurface:
      break
    }
  }

  func appendScrollIndicatorSemantics(
    for node: PlacedNode,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    modalFocusScopePath: [Identity]?,
    clippedTo clipRect: CellRect?,
    interactionRegions: inout [InteractionRegion],
    focusRegions: inout [FocusRegion],
    nextHitTestOrder: inout Int
  ) {
    guard let axes = node.drawMetadata.scrollIndicatorAxes else {
      return
    }

    for axis in [ScrollIndicatorAxis.vertical, .horizontal] {
      guard
        let metrics = resolvedScrollIndicatorMetrics(
          viewportRect: node.bounds,
          contentBounds: node.contentBounds,
          axes: axes,
          axis: axis
        ),
        let clippedRect = clippedRect(for: metrics.rect, clippedTo: clipRect)
      else {
        continue
      }

      let identity: Identity
      switch axis {
      case .vertical:
        identity = verticalScrollIndicatorIdentity(for: node.identity)
      case .horizontal:
        identity = horizontalScrollIndicatorIdentity(for: node.identity)
      }

      interactionRegions.append(
        InteractionRegion(
          identity: identity,
          rect: clippedRect,
          routeID: primaryRouteID(for: identity, ownerNodeID: node.viewNodeID),
          hitTestOrder: nextHitTestOrder,
          captureOnPress: true
        )
      )
      nextHitTestOrder += 1
      focusRegions.append(
        FocusRegion(
          identity: identity,
          rect: clippedRect,
          focusInteractions: .edit,
          scopePath: scopePath,
          sectionIdentity: sectionIdentity,
          modalFocusScopePath: modalFocusScopePath
        )
      )
    }
  }

  private func appendListSemantics(
    for node: PlacedNode,
    payload: ListPayload,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    modalFocusScopePath: [Identity]?,
    clippedTo clipRect: CellRect?,
    sealingParentOnChain: Bool,
    interactionRegions: inout [InteractionRegion],
    focusRegions: inout [FocusRegion],
    nextHitTestOrder: inout Int
  ) {
    let layout = payload.style.visibleListLayout(
      for: payload,
      in: node.bounds
    )

    for (lineIndex, line) in layout.lines.enumerated() {
      guard let rowIndex = line.rowIndex else {
        continue
      }

      let lineRect = CellRect(
        origin: .init(
          x: layout.contentBounds.origin.x,
          y: layout.contentBounds.origin.y + lineIndex
        ),
        size: .init(
          width: layout.contentBounds.size.width,
          height: 1
        )
      )
      guard let clippedRect = clippedRect(for: lineRect, clippedTo: clipRect) else {
        continue
      }

      let identity = listRowIdentity(
        for: node.identity,
        rowIndex: rowIndex
      )
      interactionRegions.append(
        InteractionRegion(
          identity: identity,
          rect: clippedRect,
          routeID: primaryRouteID(for: identity, ownerNodeID: node.viewNodeID),
          hitTestOrder: nextHitTestOrder,
          captureOnPress: node.semanticMetadata.captureOnPress
        )
      )
      nextHitTestOrder += 1
      if !sealingParentOnChain {
        focusRegions.append(
          FocusRegion(
            identity: identity,
            rect: clippedRect,
            focusInteractions: .activate,
            scopePath: scopePath,
            sectionIdentity: sectionIdentity ?? node.identity,
            modalFocusScopePath: modalFocusScopePath
          )
        )
      }
    }
  }

  private func appendTableSemantics(
    for node: PlacedNode,
    payload: TablePayload,
    clippedTo clipRect: CellRect?,
    interactionRegions: inout [InteractionRegion],
    nextHitTestOrder: inout Int
  ) {
    let layout = DrawExtractor().visibleTableLayout(
      for: payload,
      in: node.bounds
    )

    for (lineIndex, line) in layout.lines.enumerated() {
      guard line.role == .row, let rowIndex = line.rowIndex else {
        continue
      }
      guard payload.rows.indices.contains(rowIndex), payload.rows[rowIndex].tag != nil else {
        continue
      }

      let lineRect = CellRect(
        origin: .init(
          x: node.bounds.origin.x,
          y: node.bounds.origin.y + lineIndex
        ),
        size: .init(
          width: node.bounds.size.width,
          height: 1
        )
      )
      guard let clippedRect = clippedRect(for: lineRect, clippedTo: clipRect) else {
        continue
      }

      let identity = tableRowIdentity(
        for: node.identity,
        rowIndex: rowIndex
      )
      interactionRegions.append(
        InteractionRegion(
          identity: identity,
          rect: clippedRect,
          routeID: primaryRouteID(for: identity, ownerNodeID: node.viewNodeID),
          hitTestOrder: nextHitTestOrder,
          captureOnPress: node.semanticMetadata.captureOnPress
        )
      )
      nextHitTestOrder += 1
    }
  }

  private func appendRichTextSemantics(
    for node: PlacedNode,
    payload: RichTextPayload,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    modalFocusScopePath: [Identity]?,
    clippedTo clipRect: CellRect?,
    sealingParentOnChain: Bool,
    interactionRegions: inout [InteractionRegion],
    focusRegions: inout [FocusRegion],
    nextHitTestOrder: inout Int
  ) {
    guard node.bounds.size.width > 0, node.bounds.size.height > 0, payload.linkCount > 0 else {
      return
    }

    let layout = layoutRichText(
      for: payload,
      options: .init(
        width: node.bounds.size.width,
        lineLimit: node.layoutMetadata.lineLimit,
        truncationMode: node.layoutMetadata.textTruncationMode ?? .tail,
        wrappingStrategy: node.layoutMetadata.textWrappingStrategy ?? .wordBoundary
      )
    )
    var focusRegionIndices: [Identity: Int] = [:]

    for (lineIndex, line) in layout.lines.prefix(node.bounds.size.height).enumerated() {
      var fragmentIdentity: Identity?
      var fragmentStartX: Int?
      var fragmentWidth = 0
      var x = 0

      func flushFragment() {
        guard
          let fragmentIdentity,
          let fragmentStartX,
          fragmentWidth > 0
        else {
          return
        }

        let rect = CellRect(
          origin: .init(
            x: node.bounds.origin.x + fragmentStartX,
            y: node.bounds.origin.y + lineIndex
          ),
          size: .init(width: fragmentWidth, height: 1)
        )
        guard let clippedRect = clippedRect(for: rect, clippedTo: clipRect) else {
          return
        }

        interactionRegions.append(
          InteractionRegion(
            identity: fragmentIdentity,
            rect: clippedRect,
            routeID: primaryRouteID(for: fragmentIdentity, ownerNodeID: node.viewNodeID),
            hitTestOrder: nextHitTestOrder,
            captureOnPress: node.semanticMetadata.captureOnPress
          )
        )
        nextHitTestOrder += 1

        // Focus regions from descendants are suppressed when an ancestor seals
        // focus. Pointer hit-testing stays active because sealing is a keyboard
        // traversal rule, not a mouse interaction rule.
        guard !sealingParentOnChain else {
          return
        }

        if let existingIndex = focusRegionIndices[fragmentIdentity] {
          focusRegions[existingIndex].rect = union(
            focusRegions[existingIndex].rect,
            clippedRect
          )
        } else {
          focusRegionIndices[fragmentIdentity] = focusRegions.count
          focusRegions.append(
            FocusRegion(
              identity: fragmentIdentity,
              rect: clippedRect,
              focusInteractions: .activate,
              scopePath: scopePath,
              sectionIdentity: sectionIdentity,
              modalFocusScopePath: modalFocusScopePath
            )
          )
        }
      }

      for cluster in line.clusters {
        let clusterWidth = max(1, cluster.cellWidth)
        let clusterIdentity = cluster.runIndex.flatMap { runIndex -> Identity? in
          guard payload.runs.indices.contains(runIndex),
            let identifier = payload.runs[runIndex].linkIdentifier
          else {
            return nil
          }
          return inlineLinkIdentity(
            parent: node.identity,
            identifier: identifier
          )
        }

        if clusterIdentity != fragmentIdentity {
          flushFragment()
          fragmentIdentity = clusterIdentity
          fragmentStartX = clusterIdentity == nil ? nil : x
          fragmentWidth = clusterIdentity == nil ? 0 : clusterWidth
        } else if clusterIdentity != nil {
          fragmentWidth += clusterWidth
        }

        x += clusterWidth
      }

      flushFragment()
    }
  }

  private func clippedRect(
    for rect: CellRect,
    clippedTo clipRect: CellRect?
  ) -> CellRect? {
    if rect.isEmpty {
      return nil
    }
    guard let clipRect else {
      return rect
    }
    return rect.intersection(clipRect)
  }

  private func union(
    _ lhs: CellRect,
    _ rhs: CellRect
  ) -> CellRect {
    let minX = min(lhs.origin.x, rhs.origin.x)
    let minY = min(lhs.origin.y, rhs.origin.y)
    let maxX = max(lhs.maxX, rhs.maxX)
    let maxY = max(lhs.maxY, rhs.maxY)

    return CellRect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }
}
