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
    // Scope chains of the command/chrome-hosting regions (Role A: `Panel`,
    // `NavigationStack`, …) visible this frame. A host is a focus *scope* but
    // never a focus *target* — it does not participate in top-level focus, so it
    // emits no focus region at all (nothing to prune). Each path includes the
    // host's own scope identity (a host is a `focusScopeBoundary`). After the
    // walk these resolve to `SemanticSnapshot.activeCommandScopePath`.
    var commandHostScopePaths: [[Identity]] = []
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
        let hitTestingDisabledOnChain = context.hitTestingDisabledOnChain
        let isEnabled = node.environmentSnapshot.style.isEnabled
        let interactionsEnabled =
          isEnabled
          && !interactionsDisabledOnChain
          && node.semanticMetadata.interactionAvailability.isEnabled
        let allowsPointerHitTesting =
          !hitTestingDisabledOnChain
          && node.semanticMetadata.allowsHitTesting
        let routeID = primaryRouteID(
          for: node.semanticMetadata.explicitRouteIdentity ?? node.identity,
          ownerNodeID: node.viewNodeID
        )

        let participatesInTopLevelFocus = node.participatesInTopLevelFocus

        if isEnabled, let name = node.semanticMetadata.namedCoordinateSpaceName {
          namedCoordinateSpaces[name] = node.bounds
        }

        // A command/chrome host (Role A) is a focus scope but not a focus
        // target — it does not participate in top-level focus, so it never
        // reaches the focus-region emission below. Record its scope chain
        // separately for the active/visible context. Its descendants stay
        // reachable unless it also seals (a `.sealed` Panel), which the walk's
        // `sealingParentOnChain` already enforces.
        if node.semanticMetadata.isCommandHost, interactionsEnabled, !sealingParentOnChain {
          commandHostScopePaths.append(scopePath)
        }

        if participatesInTopLevelFocus, interactionsEnabled, !sealingParentOnChain {
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
          && allowsPointerHitTesting
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
            allowsPointerHitTesting: allowsPointerHitTesting,
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
              contentBounds: node.contentBounds,
              structuralHostChain: context.structuralHostChain
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
        let allowsPointerHitTesting =
          !context.hitTestingDisabledOnChain
          && node.semanticMetadata.allowsHitTesting
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
            allowsPointerHitTesting: allowsPointerHitTesting,
            interactionRegions: &interactionRegions,
            focusRegions: &focusRegions,
            nextHitTestOrder: &nextHitTestOrder
          )
        }
      }
    )

    let activeCommandScopePath = resolveActiveCommandScopePath(from: commandHostScopePaths)

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

  /// Resolves the active/visible-context scope chain from the command hosts
  /// visible this frame. SwiftUI-faithful (the "M2" rule): with no focus, a key
  /// command activates by visible context only when that context is
  /// unambiguous.
  ///
  /// Returns the deepest host's scope chain **iff** every visible host lies on
  /// that single nested chain (each is an ancestor — a prefix — of the deepest),
  /// so the hosts are totally ordered by nesting. If two hosts diverge (a split
  /// or multi-pane layout with no shared deepest descendant), the active context
  /// is ambiguous and resolves to empty: a key command then fires nothing, and
  /// the app is expected to set focus to disambiguate. A single host — or a
  /// straight nested stack of them — always resolves. Each path already includes
  /// its host's own scope identity, so dispatch walks the full host chain
  /// shallowest-first.
  private func resolveActiveCommandScopePath(
    from hostScopePaths: [[Identity]]
  ) -> [Identity] {
    guard let deepest = hostScopePaths.max(by: { $0.count < $1.count }) else {
      return []
    }
    let allOnSingleChain = hostScopePaths.allSatisfy { deepest.starts(with: $0) }
    return allOnSingleChain ? deepest : []
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
    /// `true` when an ancestor has disabled pointer hit testing. Unlike
    /// `interactionsDisabledOnChain`, this suppresses only pointer regions;
    /// keyboard focus and key-driven interaction remain available.
    let hitTestingDisabledOnChain: Bool
    /// The walk-parent identities recorded at each identity re-root boundary
    /// (`.id(_:)` entity hosts, portal-hosted content) above this node,
    /// outermost first. Identity-prefix containment checks cannot cross a
    /// re-root; this chain preserves the placed tree's structural containment
    /// for scope matching (scroll reader scopes are the consumer).
    var structuralHostChain: [Identity] = []
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
          interactionsDisabledOnChain: false,
          hitTestingDisabledOnChain: false
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
          interactionsDisabledOnChain: frame.context.interactionsDisabledOnChain,
          hitTestingDisabledOnChain: frame.context.hitTestingDisabledOnChain,
          structuralHostChain: frame.context.structuralHostChain
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
            || !frame.node.semanticMetadata.interactionAvailability.isEnabled,
          hitTestingDisabledOnChain: frame.context.hitTestingDisabledOnChain
            || !frame.node.semanticMetadata.allowsHitTesting,
          structuralHostChain: frame.context.structuralHostChain
        )
        for child in frame.node.children.reversed() {
          var context = childContext
          // A child whose identity does not extend this node's is an
          // identity re-root boundary; record this node as its structural
          // host so containment queries can cross the boundary.
          if child.identity != frame.node.identity,
            !child.identity.isDescendant(of: frame.node.identity)
          {
            context.structuralHostChain.append(frame.node.identity)
          }
          stack.append(
            Frame(
              node: child,
              context: context,
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
      // A lazy container's never-placed children have no placed nodes for
      // the walk to visit — publish their allocation-derived estimates so a
      // `scrollTo` can target an out-of-window row (the estimate is the
      // exact frame placement would assign).
      if let childScrollIdentity,
        let estimates = frame.node.lazyChildScrollEstimates
      {
        for estimate in estimates where !estimate.rect.isEmpty {
          targets.append(
            ScrollTarget(
              identity: estimate.identity,
              scrollIdentity: childScrollIdentity,
              rect: estimate.rect
            )
          )
        }
      }
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
