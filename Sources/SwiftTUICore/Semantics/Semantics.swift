/// Extracts focus, interaction, action, selection, and scroll routing from a
/// placed tree.
package struct SemanticExtractor: Sendable {
  /// Whether to run the `accessibilityWarnings` full-tree walk. Its output is
  /// consumed ONLY by the accessibility/JSON renderers (`.accessible`/`.json`
  /// output modes); no focus/scroll/routing/TUI consumer reads it. Default
  /// `true` preserves behavior; the runtime passes `false` for the common
  /// terminal (`.tui`) path so the walk becomes dead work it can skip.
  private let extractsAccessibilityWarnings: Bool

  package init() {
    self.init(extractsAccessibilityWarnings: true)
  }

  /// Package initializer that lets the runtime disable the accessibility-warnings
  /// walk for non-accessibility output. Kept `package` so the optimization flag
  /// stays off the public API surface (the public `init()` is unchanged).
  package init(extractsAccessibilityWarnings: Bool) {
    self.extractsAccessibilityWarnings = extractsAccessibilityWarnings
  }

  /// Extracts semantic routing data from `placed`.
  ///
  /// The input is the effective placed tree for the current frame: retained
  /// placement has already refreshed resolved-derived mirrors, and animation
  /// overlays may already be injected. Transient overlay nodes are filtered
  /// here so routing remains tied to the committed tree.
  package func extract(from placed: PlacedNode) -> SemanticSnapshot {
    var interactionRegions: [InteractionRegion] = []
    var focusRegions: [FocusRegion] = []
    // Identities of command/chrome-hosting regions (open `Panel`s). They are
    // focus *scopes* but never focus *targets*: every region they emit is pruned
    // after the walk (see below), so Tab lands on item leaves, not the host.
    var transparentFocusContainerIDs: Set<Identity> = []
    // Scope chain of the deepest visible hosting region — the active/visible
    // context for key-command dispatch when nothing is focused. Updated in
    // pre-order, so the last-entered host at the greatest depth wins (the
    // frontmost-ish visible host). See `SemanticSnapshot.activeCommandScopePath`.
    var activeCommandScopePath: [Identity] = []
    var scrollRoutes: [ScrollRoute] = []
    var selectionRoutes: [SelectionRoute] = []
    var namedCoordinateSpaces: [String: CellRect] = [:]
    var hitTestOrder = 0

    walk(
      placed,
      hitTestOrder: &hitTestOrder,
      preVisit: { node, context, order, nextHitTestOrder in
        let scopePath = context.scopePath
        let sectionIdentity = context.sectionIdentity
        let modalFocusScopePath = context.modalFocusScopePath
        let clipRect = context.clipRect
        let sealingParentOnChain = context.sealingParentOnChain
        let interactionsDisabledOnChain = context.interactionsDisabledOnChain
        let isEnabled = node.environmentSnapshot.style.isEnabled
        let interactionsEnabled =
          isEnabled
          && !interactionsDisabledOnChain
          && node.semanticMetadata.interactionAvailability.isEnabled
        let hitsAllowed = node.semanticMetadata.allowsHitTesting
        let routeID = primaryRouteID(
          for: node.identity,
          ownerNodeID: node.viewNodeID
        )

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
          // An open `Panel` is a command/chrome host, not a focus target: its
          // emitted region is pruned after the walk so Tab passes through to the
          // item leaves. A `.sealed` Panel is the deliberate stop and keeps its
          // own target. The host's scope chain (`scopePath` already includes its
          // own scope identity, since a `Panel` is a `focusScopeBoundary`) feeds
          // the active/visible context used for command dispatch without focus.
          if case .view("Panel") = node.kind,
            !node.semanticMetadata.sealsFocusDescendants
          {
            transparentFocusContainerIDs.insert(node.identity)
            if scopePath.count >= activeCommandScopePath.count {
              activeCommandScopePath = scopePath
            }
          }
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
              viewNodeID: node.viewNodeID,
              viewportRect: node.bounds,
              contentBounds: node.contentBounds
            )
          )
          selectionRoutes.append(
            SelectionRoute(identity: node.identity, role: scrollRole)
          )
        }
      },
      postVisit: { node, context, nextHitTestOrder in
        let scopePath = context.scopePath
        let sectionIdentity = context.sectionIdentity
        let modalFocusScopePath = context.modalFocusScopePath
        let clipRect = context.clipRect
        let sealingParentOnChain = context.sealingParentOnChain
        let interactionsDisabledOnChain = context.interactionsDisabledOnChain
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

    // A command/chrome-hosting region (an open `Panel`) is never a focus target.
    // Drop every region it emitted so Tab lands on item leaves in reading order,
    // matching SwiftUI (containers guide focus order; only leaves are focused).
    // This is scoped to hosting containers, not all scope boundaries: intentional
    // item targets (e.g. List rows) stay focusable, and a `.sealed` Panel keeps
    // its region (the deliberate focus stop). A bare host with no focusable child
    // is no longer focusable either — its commands fire via the active/visible
    // context (`activeCommandScopePath`), not by focusing the host.
    if !transparentFocusContainerIDs.isEmpty {
      focusRegions.removeAll { transparentFocusContainerIDs.contains($0.identity) }
    }

    let scrollTargets = scrollTargets(from: placed)
    let accessibilityNodes = accessibilityNodes(
      from: placed,
      focusRegions: focusRegions
    )
    let accessibilityWarnings =
      extractsAccessibilityWarnings ? accessibilityWarnings(from: placed) : []

    return SemanticSnapshot(
      interactionRegions: interactionRegions,
      focusRegions: focusRegions,
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets,
      selectionRoutes: selectionRoutes,
      namedCoordinateSpaces: namedCoordinateSpaces,
      accessibilityNodes: accessibilityNodes,
      accessibilityWarnings: accessibilityWarnings,
      activeCommandScopePath: activeCommandScopePath
    )
  }

  package func extract(
    from placed: PlacedNode,
    retained input: RetainedSemanticExtractionInput?
  ) -> SemanticSnapshot {
    if let input, input.proof == .wholeTreeIdentical {
      return input.previousSnapshot
    }
    return extract(from: placed)
  }
}

extension SemanticExtractor {
  /// The per-node traversal context threaded through the semantics walk.
  ///
  /// Bundles the routing state that each node inherits from its ancestors so
  /// the visitor closures and recursive frames forward a single labeled value
  /// instead of a long positional argument list. Child contexts are derived by
  /// copying with modification, mirroring the original frame propagation.
  struct VisitContext {
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
  }

  private func walk(
    _ node: PlacedNode,
    scopePath: [Identity] = [],
    sectionIdentity: Identity? = nil,
    clipRect: CellRect? = nil,
    hitTestOrder: inout Int,
    preVisit: (PlacedNode, VisitContext, Int, inout Int) -> Void,
    postVisit: (PlacedNode, VisitContext, inout Int) -> Void
  ) {
    enum Phase {
      case enter
      case exit
    }

    struct Frame {
      let node: PlacedNode
      let context: VisitContext
      let phase: Phase
    }

    var stack: [Frame] = [
      Frame(
        node: node,
        context: VisitContext(
          scopePath: scopePath,
          sectionIdentity: sectionIdentity,
          modalFocusScopePath: nil,
          clipRect: clipRect,
          sealingParentOnChain: false,
          interactionsDisabledOnChain: false
        ),
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
          ? frame.context.scopePath + [focusScopeIdentity]
          : frame.context.scopePath
        let nodeSectionIdentity =
          frame.node.semanticMetadata.focusSectionBoundary
          ? frame.node.identity
          : frame.context.sectionIdentity
        let nodeModalFocusScopePath =
          isModalPresentationRole(frame.node.semanticMetadata.accessibilityRole)
          ? nodeScopePath
          : frame.context.modalFocusScopePath
        let nodeClipRect = combinedClipRect(
          inherited: frame.context.clipRect,
          next: frame.node.clipBounds
        )
        let nodeContext = VisitContext(
          scopePath: nodeScopePath,
          sectionIdentity: nodeSectionIdentity,
          modalFocusScopePath: nodeModalFocusScopePath,
          clipRect: nodeClipRect,
          sealingParentOnChain: frame.context.sealingParentOnChain,
          interactionsDisabledOnChain: frame.context.interactionsDisabledOnChain
        )
        let nodeHitTestOrder = hitTestOrder
        hitTestOrder += 1

        preVisit(
          frame.node,
          nodeContext,
          nodeHitTestOrder,
          &hitTestOrder
        )

        stack.append(
          Frame(
            node: frame.node,
            context: nodeContext,
            phase: .exit
          )
        )

        let childContext = VisitContext(
          scopePath: nodeScopePath,
          sectionIdentity: nodeSectionIdentity,
          modalFocusScopePath: nodeModalFocusScopePath,
          clipRect: nodeClipRect,
          sealingParentOnChain: frame.context.sealingParentOnChain
            || frame.node.semanticMetadata.sealsFocusDescendants,
          interactionsDisabledOnChain: frame.context.interactionsDisabledOnChain
            || !frame.node.semanticMetadata.interactionAvailability.isEnabled
        )
        for child in frame.node.children.reversed() {
          stack.append(
            Frame(
              node: child,
              context: childContext,
              phase: .enter
            )
          )
        }
      case .exit:
        postVisit(
          frame.node,
          frame.context,
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
