/// Extracts focus, interaction, action, selection, and scroll routing from a
/// placed tree.
public struct SemanticExtractor {
  public init() {}

  /// Extracts semantic routing data from `placed`.
  public func extract(from placed: PlacedNode) -> SemanticSnapshot {
    var interactionRegions: [InteractionRegion] = []
    var focusRegions: [FocusRegion] = []
    var scrollRoutes: [ScrollRoute] = []
    var selectionRoutes: [SelectionRoute] = []
    var hitTestOrder = 0

    walk(
      placed,
      hitTestOrder: &hitTestOrder,
      preVisit: {
        node,
        scopePath,
        sectionIdentity,
        clipRect,
        order,
        nextHitTestOrder
        in
        let isEnabled = node.environmentSnapshot.style.isEnabled
        let routeID = parallelPrimaryRouteID(for: node.identity)

        let participatesInTopLevelFocus = node.participatesInTopLevelFocus

        if participatesInTopLevelFocus, isEnabled {
          focusRegions.append(
            FocusRegion(
              identity: node.identity,
              rect: node.bounds,
              focusInteractions: node.semanticMetadata.focusInteractions,
              scopePath: scopePath,
              sectionIdentity: sectionIdentity
            )
          )
        }

        if isEnabled
          && (participatesInTopLevelFocus
            || node.semanticMetadata.participatesInPointerHitTesting)
          && interactionRect(
            for: node,
            clippedTo: clipRect
          ) != nil
        {
          interactionRegions.append(
            InteractionRegion(
              identity: node.identity,
              rect: interactionRect(for: node, clippedTo: clipRect) ?? node.bounds,
              routeID: routeID,
              hitTestOrder: order
            )
          )
        }

        if isEnabled {
          appendPayloadInteractionRegions(
            for: node,
            clippedTo: clipRect,
            interactionRegions: &interactionRegions,
            nextHitTestOrder: &nextHitTestOrder
          )
        }

        if isEnabled, let scrollRole = node.semanticMetadata.scrollRole {
          scrollRoutes.append(
            ScrollRoute(
              identity: node.identity,
              viewportRect: node.bounds,
              contentBounds: node.contentBounds
            )
          )
          selectionRoutes.append(
            SelectionRoute(identity: node.identity, role: scrollRole)
          )
        }
      },
      postVisit: {
        node,
        scopePath,
        sectionIdentity,
        clipRect,
        nextHitTestOrder
        in
        guard node.environmentSnapshot.style.isEnabled else {
          return
        }

        appendScrollIndicatorSemantics(
          for: node,
          scopePath: scopePath,
          sectionIdentity: sectionIdentity,
          clippedTo: clipRect,
          interactionRegions: &interactionRegions,
          focusRegions: &focusRegions,
          nextHitTestOrder: &nextHitTestOrder
        )
      }
    )

    return SemanticSnapshot(
      interactionRegions: interactionRegions,
      focusRegions: focusRegions,
      scrollRoutes: scrollRoutes,
      selectionRoutes: selectionRoutes
    )
  }
}

extension SemanticExtractor {
  private func walk(
    _ node: PlacedNode,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil,
    clipRect: Rect? = nil,
    hitTestOrder: inout Int,
    preVisit: (PlacedNode, [Identity], Identity?, Rect?, Int, inout Int) -> Void,
    postVisit: (PlacedNode, [Identity], Identity?, Rect?, inout Int) -> Void
  ) {
    let nodeScopePath =
      node.semanticMetadata.focusScopeBoundary
      ? scopePath + [node.identity]
      : scopePath
    let nodeSectionIdentity =
      node.semanticMetadata.focusSectionBoundary
      ? node.identity
      : sectionIdentity
    let nodeClipRect = combinedClipRect(
      inherited: clipRect,
      next: node.clipBounds
    )
    let nodeHitTestOrder = hitTestOrder
    hitTestOrder += 1

    preVisit(
      node,
      nodeScopePath,
      nodeSectionIdentity,
      nodeClipRect,
      nodeHitTestOrder,
      &hitTestOrder
    )
    for child in node.children {
      walk(
        child,
        scopePath: nodeScopePath,
        sectionIdentity: nodeSectionIdentity,
        clipRect: nodeClipRect,
        hitTestOrder: &hitTestOrder,
        preVisit: preVisit,
        postVisit: postVisit
      )
    }
    postVisit(
      node,
      nodeScopePath,
      nodeSectionIdentity,
      nodeClipRect,
      &hitTestOrder
    )
  }

  private func combinedClipRect(
    inherited: Rect?,
    next: Rect?
  ) -> Rect? {
    switch (inherited, next) {
    case (.none, .none):
      nil
    case (.some(let inherited), .none):
      inherited
    case (.none, .some(let next)):
      next
    case (.some(let inherited), .some(let next)):
      inherited.intersection(next)
    }
  }

  private func interactionRect(
    for node: PlacedNode,
    clippedTo clipRect: Rect?
  ) -> Rect? {
    guard let clipRect else {
      return node.bounds.isEmpty ? nil : node.bounds
    }
    return node.bounds.intersection(clipRect)
  }

  private func appendPayloadInteractionRegions(
    for node: PlacedNode,
    clippedTo clipRect: Rect?,
    interactionRegions: inout [InteractionRegion],
    nextHitTestOrder: inout Int
  ) {
    switch node.drawPayload {
    case .list(let payload):
      let layout = DrawExtractor().visibleListLayout(
        for: payload,
        in: node.bounds
      )

      for (lineIndex, line) in layout.lines.enumerated() {
        guard let rowIndex = line.rowIndex else {
          continue
        }

        let lineRect = Rect(
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

        let identity = parallelListRowIdentity(
          for: node.identity,
          rowIndex: rowIndex
        )
        interactionRegions.append(
          InteractionRegion(
            identity: identity,
            rect: clippedRect,
            routeID: parallelPrimaryRouteID(for: identity),
            hitTestOrder: nextHitTestOrder
          )
        )
        nextHitTestOrder += 1
      }
    case .table(let payload):
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

        let lineRect = Rect(
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

        let identity = parallelTableRowIdentity(
          for: node.identity,
          rowIndex: rowIndex
        )
        interactionRegions.append(
          InteractionRegion(
            identity: identity,
            rect: clippedRect,
            routeID: parallelPrimaryRouteID(for: identity),
            hitTestOrder: nextHitTestOrder
          )
        )
        nextHitTestOrder += 1
      }
    case .none, .rule, .shape, .text, .image:
      break
    }
  }

  private func appendScrollIndicatorSemantics(
    for node: PlacedNode,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    clippedTo clipRect: Rect?,
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
        identity = parallelVerticalScrollIndicatorIdentity(for: node.identity)
      case .horizontal:
        identity = parallelHorizontalScrollIndicatorIdentity(for: node.identity)
      }

      interactionRegions.append(
        InteractionRegion(
          identity: identity,
          rect: clippedRect,
          routeID: parallelPrimaryRouteID(for: identity),
          hitTestOrder: nextHitTestOrder
        )
      )
      nextHitTestOrder += 1
      focusRegions.append(
        FocusRegion(
          identity: identity,
          rect: clippedRect,
          focusInteractions: .edit,
          scopePath: scopePath,
          sectionIdentity: sectionIdentity
        )
      )
    }
  }

  private func clippedRect(
    for rect: Rect,
    clippedTo clipRect: Rect?
  ) -> Rect? {
    if rect.isEmpty {
      return nil
    }
    guard let clipRect else {
      return rect
    }
    return rect.intersection(clipRect)
  }
}
