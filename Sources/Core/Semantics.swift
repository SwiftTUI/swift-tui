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
        let hitsAllowed = node.semanticMetadata.allowsHitTesting
        let routeID = primaryRouteID(for: node.identity)

        let participatesInTopLevelFocus = node.participatesInTopLevelFocus

        if participatesInTopLevelFocus, isEnabled, hitsAllowed {
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
          && hitsAllowed
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
          appendPayloadSemantics(
            for: node,
            scopePath: scopePath,
            sectionIdentity: sectionIdentity,
            clippedTo: clipRect,
            interactionRegions: &interactionRegions,
            focusRegions: &focusRegions,
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
    enum Phase {
      case enter
      case exit
    }

    struct Frame {
      let node: PlacedNode
      let scopePath: [Identity]
      let sectionIdentity: Identity?
      let clipRect: Rect?
      let phase: Phase
    }

    var stack: [Frame] = [
      Frame(
        node: node,
        scopePath: scopePath,
        sectionIdentity: sectionIdentity,
        clipRect: clipRect,
        phase: .enter
      )
    ]

    while let frame = stack.popLast() {
      // Transient nodes (animation removal overlays) render but do
      // not contribute to semantics, focus, or interaction routing.
      // Skip them and their entire subtree — the committed tree is
      // the authoritative source for routing.
      if frame.node.isTransient { continue }
      switch frame.phase {
      case .enter:
        let nodeScopePath =
          frame.node.semanticMetadata.focusScopeBoundary
          ? frame.scopePath + [frame.node.identity]
          : frame.scopePath
        let nodeSectionIdentity =
          frame.node.semanticMetadata.focusSectionBoundary
          ? frame.node.identity
          : frame.sectionIdentity
        let nodeClipRect = combinedClipRect(
          inherited: frame.clipRect,
          next: frame.node.clipBounds
        )
        let nodeHitTestOrder = hitTestOrder
        hitTestOrder += 1

        preVisit(
          frame.node,
          nodeScopePath,
          nodeSectionIdentity,
          nodeClipRect,
          nodeHitTestOrder,
          &hitTestOrder
        )

        stack.append(
          Frame(
            node: frame.node,
            scopePath: nodeScopePath,
            sectionIdentity: nodeSectionIdentity,
            clipRect: nodeClipRect,
            phase: .exit
          )
        )

        for child in frame.node.children.reversed() {
          stack.append(
            Frame(
              node: child,
              scopePath: nodeScopePath,
              sectionIdentity: nodeSectionIdentity,
              clipRect: nodeClipRect,
              phase: .enter
            )
          )
        }
      case .exit:
        postVisit(
          frame.node,
          frame.scopePath,
          frame.sectionIdentity,
          frame.clipRect,
          &hitTestOrder
        )
      }
    }
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

  private func appendPayloadSemantics(
    for node: PlacedNode,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    clippedTo clipRect: Rect?,
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
        clippedTo: clipRect,
        interactionRegions: &interactionRegions,
        focusRegions: &focusRegions,
        nextHitTestOrder: &nextHitTestOrder
      )
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

        let identity = listRowIdentity(
          for: node.identity,
          rowIndex: rowIndex
        )
        interactionRegions.append(
          InteractionRegion(
            identity: identity,
            rect: clippedRect,
            routeID: primaryRouteID(for: identity),
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

        let identity = tableRowIdentity(
          for: node.identity,
          rowIndex: rowIndex
        )
        interactionRegions.append(
          InteractionRegion(
            identity: identity,
            rect: clippedRect,
            routeID: primaryRouteID(for: identity),
            hitTestOrder: nextHitTestOrder
          )
        )
        nextHitTestOrder += 1
      }
    case .none, .rule, .shape, .text, .image:
      break
    }
  }

  private func appendRichTextSemantics(
    for node: PlacedNode,
    payload: RichTextPayload,
    scopePath: [Identity],
    sectionIdentity: Identity?,
    clippedTo clipRect: Rect?,
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

        let rect = Rect(
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
            routeID: primaryRouteID(for: fragmentIdentity),
            hitTestOrder: nextHitTestOrder
          )
        )
        nextHitTestOrder += 1

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
              sectionIdentity: sectionIdentity
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
        identity = verticalScrollIndicatorIdentity(for: node.identity)
      case .horizontal:
        identity = horizontalScrollIndicatorIdentity(for: node.identity)
      }

      interactionRegions.append(
        InteractionRegion(
          identity: identity,
          rect: clippedRect,
          routeID: primaryRouteID(for: identity),
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

  private func union(
    _ lhs: Rect,
    _ rhs: Rect
  ) -> Rect {
    let minX = min(lhs.origin.x, rhs.origin.x)
    let minY = min(lhs.origin.y, rhs.origin.y)
    let maxX = max(lhs.maxX, rhs.maxX)
    let maxY = max(lhs.maxY, rhs.maxY)

    return Rect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }
}
