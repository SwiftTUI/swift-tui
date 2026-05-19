/// Extracts focus, interaction, action, selection, and scroll routing from a
/// placed tree.
public struct SemanticExtractor: Sendable {
  public init() {}

  /// Extracts semantic routing data from `placed`.
  ///
  /// The input is the effective placed tree for the current frame: retained
  /// placement has already refreshed resolved-derived mirrors, and animation
  /// overlays may already be injected. Transient overlay nodes are filtered
  /// here so routing remains tied to the committed tree.
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
        modalFocusScopePath,
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
              sectionIdentity: sectionIdentity,
              modalFocusScopePath: modalFocusScopePath
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
            modalFocusScopePath: modalFocusScopePath,
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
        modalFocusScopePath,
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
            modalFocusScopePath: modalFocusScopePath,
            clippedTo: clipRect,
            interactionRegions: &interactionRegions,
            focusRegions: &focusRegions,
            nextHitTestOrder: &nextHitTestOrder
          )
        }
      }
    )

    let scrollTargets = scrollTargets(from: placed)
    let accessibilityNodes = accessibilityNodes(
      from: placed,
      focusRegions: focusRegions
    )
    let accessibilityWarnings = accessibilityWarnings(from: placed)

    return SemanticSnapshot(
      interactionRegions: interactionRegions,
      focusRegions: focusRegions,
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets,
      selectionRoutes: selectionRoutes,
      namedCoordinateSpaces: namedCoordinateSpaces,
      accessibilityNodes: accessibilityNodes,
      accessibilityWarnings: accessibilityWarnings
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
    preVisit:
      (PlacedNode, [Identity], Identity?, [Identity]?, CellRect?, Int, Bool, Bool, inout Int) ->
      Void,
    postVisit: (PlacedNode, [Identity], Identity?, [Identity]?, CellRect?, Bool, Bool, inout Int) ->
      Void
  ) {
    enum Phase {
      case enter
      case exit
    }

    struct Frame {
      let node: PlacedNode
      let scopePath: [Identity]
      let sectionIdentity: Identity?
      let modalFocusScopePath: [Identity]?
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
        modalFocusScopePath: nil,
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
        let nodeModalFocusScopePath =
          isModalPresentationRole(frame.node.semanticMetadata.accessibilityRole)
          ? nodeScopePath
          : frame.modalFocusScopePath
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
          nodeModalFocusScopePath,
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
            modalFocusScopePath: nodeModalFocusScopePath,
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
              modalFocusScopePath: nodeModalFocusScopePath,
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
          frame.modalFocusScopePath,
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

  private func isModalPresentationRole(
    _ role: AccessibilityRole?
  ) -> Bool {
    switch role {
    case .alert, .confirmationDialog, .sheet:
      true
    default:
      false
    }
  }

  private func scrollTargets(from node: PlacedNode) -> [ScrollTarget] {
    struct Frame {
      var node: PlacedNode
      var activeScrollIdentity: Identity?
    }

    var targets: [ScrollTarget] = []
    var stack = [Frame(node: node, activeScrollIdentity: nil)]

    while let frame = stack.popLast() {
      if frame.node.isTransient { continue }

      if let activeScrollIdentity = frame.activeScrollIdentity,
        frame.node.identity != activeScrollIdentity
      {
        let rect = semanticBounds(for: frame.node)
        if !rect.isEmpty {
          targets.append(
            ScrollTarget(
              identity: frame.node.identity,
              scrollIdentity: activeScrollIdentity,
              rect: rect
            )
          )
        }
      }

      let childScrollIdentity =
        frame.node.semanticMetadata.scrollRole == nil
        ? frame.activeScrollIdentity
        : frame.node.identity
      for child in frame.node.children.reversed() {
        stack.append(
          Frame(
            node: child,
            activeScrollIdentity: childScrollIdentity
          )
        )
      }
    }

    return targets
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

  func semanticBounds(
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
