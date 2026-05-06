/// Extracts focus, interaction, action, selection, and scroll routing from a
/// placed tree.
public struct SemanticExtractor: Sendable {
  public init() {}

  /// Extracts semantic routing data from `placed`.
  public func extract(from placed: PlacedNode) -> SemanticSnapshot {
    var interactionRegions: [InteractionRegion] = []
    var focusRegions: [FocusRegion] = []
    var scrollRoutes: [ScrollRoute] = []
    var selectionRoutes: [SelectionRoute] = []
    var namedCoordinateSpaces: [String: CellRect] = [:]
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
        sealingParentOnChain,
        interactionsDisabledOnChain,
        nextHitTestOrder
        in
        let isEnabled = node.environmentSnapshot.style.isEnabled
        let interactionsEnabled =
          isEnabled
          && !interactionsDisabledOnChain
          && node.semanticMetadata.interactionAvailability.isEnabled
        let hitsAllowed = node.semanticMetadata.allowsHitTesting
        let routeID = primaryRouteID(for: node.identity)

        let participatesInTopLevelFocus = node.participatesInTopLevelFocus

        if isEnabled, let name = node.semanticMetadata.namedCoordinateSpaceName {
          namedCoordinateSpaces[name] = node.bounds
        }

        if participatesInTopLevelFocus, interactionsEnabled, hitsAllowed, !sealingParentOnChain {
          focusRegions.append(
            FocusRegion(
              identity: node.identity,
              rect: semanticBounds(for: node),
              focusInteractions: node.semanticMetadata.focusInteractions,
              scopePath: scopePath,
              sectionIdentity: sectionIdentity
            )
          )
        }

        if interactionsEnabled
          && hitsAllowed
          && (participatesInTopLevelFocus
            || node.semanticMetadata.participatesInPointerHitTesting)
        {
          let computedRect = interactionRect(for: node, clippedTo: clipRect)
          let explicitPath = transformedExplicitInteractionPath(for: node)
          let pathRect = explicitPath.flatMap { interactionRect(for: $0, clippedTo: clipRect) }
          let finalRect =
            pathRect
            ?? transformedExplicitInteractionRect(for: node)
            ?? computedRect
          if let finalRect {
            interactionRegions.append(
              InteractionRegion(
                identity: node.identity,
                rect: finalRect,
                routeID: routeID,
                hitTestOrder: order,
                captureOnPress: node.semanticMetadata.captureOnPress,
                contentShape: explicitPath
              )
            )
          }
        }

        if interactionsEnabled {
          appendPayloadSemantics(
            for: node,
            scopePath: scopePath,
            sectionIdentity: sectionIdentity,
            clippedTo: clipRect,
            sealingParentOnChain: sealingParentOnChain,
            interactionRegions: &interactionRegions,
            focusRegions: &focusRegions,
            nextHitTestOrder: &nextHitTestOrder
          )
        }

        if interactionsEnabled, let scrollRole = node.semanticMetadata.scrollRole {
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
        sealingParentOnChain,
        interactionsDisabledOnChain,
        nextHitTestOrder
        in
        guard node.environmentSnapshot.style.isEnabled else {
          return
        }

        if !sealingParentOnChain
          && !interactionsDisabledOnChain
          && node.semanticMetadata.interactionAvailability.isEnabled
        {
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
      }
    )

    let accessibilityNodes = accessibilityNodes(
      from: placed,
      focusRegions: focusRegions
    )

    return SemanticSnapshot(
      interactionRegions: interactionRegions,
      focusRegions: focusRegions,
      scrollRoutes: scrollRoutes,
      selectionRoutes: selectionRoutes,
      namedCoordinateSpaces: namedCoordinateSpaces,
      accessibilityNodes: accessibilityNodes
    )
  }
}

extension SemanticExtractor {
  private func walk(
    _ node: PlacedNode,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil,
    clipRect: CellRect? = nil,
    hitTestOrder: inout Int,
    preVisit: (PlacedNode, [Identity], Identity?, CellRect?, Int, Bool, Bool, inout Int) -> Void,
    postVisit: (PlacedNode, [Identity], Identity?, CellRect?, Bool, Bool, inout Int) -> Void
  ) {
    enum Phase {
      case enter
      case exit
    }

    struct Frame {
      let node: PlacedNode
      let scopePath: [Identity]
      let sectionIdentity: Identity?
      let clipRect: CellRect?
      /// `true` when an ancestor on the current walk chain is marked
      /// `sealsFocusDescendants`. Propagated to descendants so focus
      /// region emission can skip them even though the sealing node
      /// itself is emitted normally.
      let sealingParentOnChain: Bool
      let interactionsDisabledOnChain: Bool
      let phase: Phase
    }

    var stack: [Frame] = [
      Frame(
        node: node,
        scopePath: scopePath,
        sectionIdentity: sectionIdentity,
        clipRect: clipRect,
        sealingParentOnChain: false,
        interactionsDisabledOnChain: false,
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
        let focusScopeIdentity =
          frame.node.semanticMetadata.focusScopeIdentity ?? frame.node.identity
        let nodeScopePath =
          frame.node.semanticMetadata.focusScopeBoundary
          ? frame.scopePath + [focusScopeIdentity]
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
          frame.sealingParentOnChain,
          frame.interactionsDisabledOnChain,
          &hitTestOrder
        )

        stack.append(
          Frame(
            node: frame.node,
            scopePath: nodeScopePath,
            sectionIdentity: nodeSectionIdentity,
            clipRect: nodeClipRect,
            sealingParentOnChain: frame.sealingParentOnChain,
            interactionsDisabledOnChain: frame.interactionsDisabledOnChain,
            phase: .exit
          )
        )

        let childSealingParentOnChain =
          frame.sealingParentOnChain
          || frame.node.semanticMetadata.sealsFocusDescendants
        let childInteractionsDisabledOnChain =
          frame.interactionsDisabledOnChain
          || !frame.node.semanticMetadata.interactionAvailability.isEnabled
        for child in frame.node.children.reversed() {
          stack.append(
            Frame(
              node: child,
              scopePath: nodeScopePath,
              sectionIdentity: nodeSectionIdentity,
              clipRect: nodeClipRect,
              sealingParentOnChain: childSealingParentOnChain,
              interactionsDisabledOnChain: childInteractionsDisabledOnChain,
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
          frame.sealingParentOnChain,
          frame.interactionsDisabledOnChain,
          &hitTestOrder
        )
      }
    }
  }

  private func combinedClipRect(
    inherited: CellRect?,
    next: CellRect?
  ) -> CellRect? {
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
    clippedTo clipRect: CellRect?
  ) -> CellRect? {
    let semanticBounds = semanticBounds(for: node)
    guard let clipRect else {
      return semanticBounds.isEmpty ? nil : semanticBounds
    }
    return semanticBounds.intersection(clipRect)
  }

  private func semanticBounds(
    for node: PlacedNode
  ) -> CellRect {
    switch node.layoutBehavior {
    case .offset(let x, let y):
      return translated(
        node.bounds,
        by: .init(x: x, y: y)
      )
    default:
      return node.bounds
    }
  }

  private func accessibilityNodes(
    from root: PlacedNode,
    focusRegions: [FocusRegion]
  ) -> [AccessibilityNode] {
    let focusIdentities = accessibilityFocusIdentities(from: focusRegions)
    let textInputCursorAnchors = textInputAccessibilityCursorAnchors(from: root)
    var emittedSubtrees: Set<Identity> = []
    var hiddenDescendantSubtrees: Set<Identity> = []
    var stack: [(node: PlacedNode, isExit: Bool)] = [(root, false)]

    while let frame = stack.popLast() {
      let node = frame.node
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if frame.isExit {
        let childSummary = accessibilityChildSummary(
          for: node,
          emittedSubtrees: emittedSubtrees,
          hiddenDescendantSubtrees: hiddenDescendantSubtrees
        )
        if accessibilitySelfIsRelevant(node, focusIdentities: focusIdentities)
          || childSummary.hasEmittedChild
        {
          emittedSubtrees.insert(node.identity)
        }
        if childSummary.hasHiddenDescendant {
          hiddenDescendantSubtrees.insert(node.identity)
        }
      } else {
        stack.append((node, true))
        for child in node.children.reversed() {
          stack.append((child, false))
        }
      }
    }

    var nodes: [AccessibilityNode] = []
    var emitStack: [(node: PlacedNode, emittedParentIdentity: Identity?)] = [(root, nil)]
    while let frame = emitStack.popLast() {
      let node = frame.node
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      let emits = emittedSubtrees.contains(node.identity)
      var childParentIdentity = frame.emittedParentIdentity
      if emits {
        let childSummary = accessibilityChildSummary(
          for: node,
          emittedSubtrees: emittedSubtrees,
          hiddenDescendantSubtrees: hiddenDescendantSubtrees
        )
        if let accessibilityNode = accessibilityNode(
          for: node,
          parentIdentity: frame.emittedParentIdentity,
          hasEmittedChild: childSummary.hasEmittedChild,
          hasHiddenDescendant: childSummary.hasHiddenDescendant,
          focusIdentities: focusIdentities,
          textInputCursorAnchors: textInputCursorAnchors
        ) {
          nodes.append(accessibilityNode)
          childParentIdentity = node.identity
        }
      }

      for child in node.children.reversed() {
        emitStack.append((child, childParentIdentity))
      }
    }

    return nodes
  }

  private func accessibilityFocusIdentities(
    from focusRegions: [FocusRegion]
  ) -> Set<Identity> {
    var identities: Set<Identity> = []
    for region in focusRegions {
      identities.insert(region.identity)
      for scopeIdentity in region.scopePath {
        identities.insert(scopeIdentity)
      }
    }
    return identities
  }

  private func accessibilityChildSummary(
    for node: PlacedNode,
    emittedSubtrees: Set<Identity>,
    hiddenDescendantSubtrees: Set<Identity>
  ) -> (hasEmittedChild: Bool, hasHiddenDescendant: Bool) {
    var hasEmittedChild = false
    var hasHiddenDescendant = false

    for child in node.children where !child.isTransient {
      if emittedSubtrees.contains(child.identity) {
        hasEmittedChild = true
      }
      if child.semanticMetadata.accessibilityHidden
        || hiddenDescendantSubtrees.contains(child.identity)
      {
        hasHiddenDescendant = true
      }
    }

    return (hasEmittedChild, hasHiddenDescendant)
  }

  private func accessibilitySelfIsRelevant(
    _ node: PlacedNode,
    focusIdentities: Set<Identity>,
    textInputCursorAnchors: [Identity: CellPoint] = [:]
  ) -> Bool {
    node.semanticMetadata.accessibilityRole != nil
      || node.semanticMetadata.accessibilityLabel != nil
      || node.semanticMetadata.accessibilityHint != nil
      || node.semanticMetadata.accessibilityLiveRegion != nil
      || node.semanticMetadata.accessibilityCursorAnchor != nil
      || textInputCursorAnchors[node.identity] != nil
      || focusIdentities.contains(node.identity)
  }

  private func accessibilityNode(
    for node: PlacedNode,
    parentIdentity: Identity?,
    hasEmittedChild: Bool,
    hasHiddenDescendant: Bool,
    focusIdentities: Set<Identity>,
    textInputCursorAnchors: [Identity: CellPoint]
  ) -> AccessibilityNode? {
    let selfIsRelevant = accessibilitySelfIsRelevant(
      node,
      focusIdentities: focusIdentities,
      textInputCursorAnchors: textInputCursorAnchors
    )
    guard
      let role = accessibilityRole(
        for: node,
        isRelevant: selfIsRelevant,
        hasEmittedChild: hasEmittedChild
      )
    else {
      return nil
    }

    return AccessibilityNode(
      identity: node.identity,
      parentIdentity: parentIdentity,
      rect: semanticBounds(for: node),
      role: role,
      label: accessibilityLabel(for: node, role: role),
      hint: node.semanticMetadata.accessibilityHint,
      hidden: hasHiddenDescendant,
      liveRegion: node.semanticMetadata.accessibilityLiveRegion,
      cursorAnchor: textInputCursorAnchors[node.identity] ?? accessibilityCursorAnchor(for: node)
    )
  }

  private func textInputAccessibilityCursorAnchors(
    from root: PlacedNode
  ) -> [Identity: CellPoint] {
    var anchors: [Identity: CellPoint] = [:]
    var stack = [root]

    while let node = stack.popLast() {
      if node.isTransient || node.semanticMetadata.accessibilityHidden {
        continue
      }

      if let route = node.semanticMetadata.textInputAccessibilityCursorAnchor {
        let bounds = semanticBounds(for: node)
        anchors[route.ownerIdentity] = CellPoint(
          x: bounds.origin.x + route.anchor.x,
          y: bounds.origin.y + route.anchor.y
        )
      }

      for child in node.children.reversed() {
        stack.append(child)
      }
    }

    return anchors
  }

  private func accessibilityRole(
    for node: PlacedNode,
    isRelevant: Bool,
    hasEmittedChild: Bool
  ) -> AccessibilityRole? {
    if let role = node.semanticMetadata.accessibilityRole {
      return role
    }
    if isRelevant || hasEmittedChild {
      return .group
    }
    return nil
  }

  private func accessibilityLabel(
    for node: PlacedNode,
    role: AccessibilityRole
  ) -> String? {
    if let label = node.semanticMetadata.accessibilityLabel {
      return label
    }
    if accessibilityRoleInfersTextLabel(role),
      let textLabel = accessibilityTextLabel(from: node.drawPayload)
    {
      return textLabel
    }
    if accessibilityRoleInfersTabLabel(role),
      let tabLabel = node.semanticMetadata.tabItemLabel
    {
      return tabLabel.title
    }
    return nil
  }

  private func accessibilityRoleInfersTextLabel(
    _ role: AccessibilityRole
  ) -> Bool {
    switch role {
    case .button, .link, .tab, .menuItem, .heading:
      true
    default:
      false
    }
  }

  private func accessibilityRoleInfersTabLabel(
    _ role: AccessibilityRole
  ) -> Bool {
    switch role {
    case .tab, .tabPanel, .tabView:
      true
    default:
      false
    }
  }

  private func accessibilityTextLabel(
    from payload: DrawPayload
  ) -> String? {
    let label: String?
    switch payload {
    case .text(let value):
      label = value
    case .richText(let payload):
      label = payload.visibleText
    case .none, .textFigure, .image, .shape, .rule, .list, .table, .canvas,
      .foreignSurface:
      label = nil
    }
    guard let label, !label.isEmpty else {
      return nil
    }
    return label
  }

  private func accessibilityCursorAnchor(
    for node: PlacedNode
  ) -> CellPoint? {
    guard let anchor = node.semanticMetadata.accessibilityCursorAnchor else {
      return nil
    }
    let bounds = semanticBounds(for: node)
    return CellPoint(
      x: bounds.origin.x + anchor.x,
      y: bounds.origin.y + anchor.y
    )
  }

  private func transformedExplicitInteractionRect(
    for node: PlacedNode
  ) -> CellRect? {
    guard let rect = node.semanticMetadata.explicitInteractionRect else {
      return nil
    }

    // The user supplies the rect in node-local coordinates (origin =
    // top-left of the modified view). Translate by `semanticBounds`
    // — which already incorporates the `.offset` layoutBehavior — so
    // this overload is consistent with `transformedExplicitInteractionPath`
    // below. Without this translation the rect would be interpreted
    // as absolute terminal coordinates, silently misbehaving for any
    // view not placed at (0, 0).
    let bounds = semanticBounds(for: node)
    return translated(rect, by: .init(x: bounds.origin.x, y: bounds.origin.y))
  }

  private func transformedExplicitInteractionPath(
    for node: PlacedNode
  ) -> Path? {
    guard let path = node.semanticMetadata.explicitInteractionPath else {
      return nil
    }

    let bounds = semanticBounds(for: node)
    return path.translatedBy(
      dx: Double(bounds.origin.x),
      dy: Double(bounds.origin.y)
    )
  }

  private func interactionRect(
    for path: Path,
    clippedTo clipRect: CellRect?
  ) -> CellRect? {
    guard let bounds = path.boundingRect else {
      return nil
    }

    let minX = Int(bounds.origin.x.rounded(.down))
    let minY = Int(bounds.origin.y.rounded(.down))
    let maxX = Int(bounds.maxX.rounded(.up))
    let maxY = Int(bounds.maxY.rounded(.up))
    let rect = CellRect(
      origin: CellPoint(x: minX, y: minY),
      size: CellSize(width: maxX - minX, height: maxY - minY)
    )
    guard !rect.isEmpty else {
      return nil
    }
    guard let clipRect else {
      return rect
    }
    return rect.intersection(clipRect)
  }

  private func appendPayloadSemantics(
    for node: PlacedNode,
    scopePath: [Identity],
    sectionIdentity: Identity?,
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
        clippedTo: clipRect,
        sealingParentOnChain: sealingParentOnChain,
        interactionRegions: &interactionRegions,
        focusRegions: &focusRegions,
        nextHitTestOrder: &nextHitTestOrder
      )
    case .list(let payload):
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
            routeID: primaryRouteID(for: identity),
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
              sectionIdentity: sectionIdentity ?? node.identity
            )
          )
        }
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
            routeID: primaryRouteID(for: identity),
            hitTestOrder: nextHitTestOrder,
            captureOnPress: node.semanticMetadata.captureOnPress
          )
        )
        nextHitTestOrder += 1
      }
    case .none, .rule, .shape, .text, .image, .canvas, .foreignSurface:
      break
    }
  }

  private func appendRichTextSemantics(
    for node: PlacedNode,
    payload: RichTextPayload,
    scopePath: [Identity],
    sectionIdentity: Identity?,
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
            routeID: primaryRouteID(for: fragmentIdentity),
            hitTestOrder: nextHitTestOrder,
            captureOnPress: node.semanticMetadata.captureOnPress
          )
        )
        nextHitTestOrder += 1

        // Suppress descendant focus region emission when an ancestor
        // on the current walk chain sealed its focus descendants. The
        // sealing node itself is emitted normally by the pre-visit —
        // only its descendants are suppressed here.
        //
        // Focus regions from descendants are suppressed when the parent
        // seals focus (`Panel.focusContainment(.sealed)`). Interaction
        // regions are intentionally not sealed: sealing affects
        // keyboard/focus routing, not pointer hit-testing. A sealed
        // Panel's interior is still clickable if the consumer wires a
        // mouse handler; only Tab traversal is blocked.
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
          routeID: primaryRouteID(for: identity),
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
          sectionIdentity: sectionIdentity
        )
      )
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

  private func translated(
    _ rect: CellRect,
    by delta: CellPoint
  ) -> CellRect {
    CellRect(
      origin: .init(
        x: rect.origin.x + delta.x,
        y: rect.origin.y + delta.y
      ),
      size: rect.size
    )
  }
}
