/// Extracts focus, interaction, action, selection, and scroll routing from a
/// placed tree.
package struct SemanticExtractor: Sendable {
  /// Whether to run the `accessibilityWarnings` full-tree walk. Its output is
  /// consumed ONLY by the JSON renderer (`.json` output mode) and the
  /// assistive-output testing seam; no focus/scroll/routing/TUI consumer reads
  /// it. Default `true` preserves behavior; the runtime passes `false` for the
  /// common terminal (`.tui`) path so the walk becomes dead work it can skip.
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
    var accessibilityActionRegions: [FocusRegion] = []
    var paragraphs: [ParagraphRegion] = []
    // Scope chains of the command/chrome-hosting regions (Role A: `Panel`,
    // `NavigationStack`, …) visible this frame. A host is a focus *scope* but
    // never a focus *target* — it does not participate in top-level focus, so it
    // emits no focus region at all (nothing to prune). Each path includes the
    // host's own scope identity (a host is a `focusScopeBoundary`). After the
    // walk these resolve to `SemanticSnapshot.activeCommandScopePath`.
    var commandHostScopePaths: [[Identity]] = []
    var scrollRoutes: [ScrollRoute] = []
    var programmaticScrollRoutes: [ScrollRoute] = []
    var selectionRoutes: [SelectionRoute] = []
    var namedCoordinateSpaces: [NamedCoordinateSpace: CellRect] = [:]
    var hitTestOrder = 0
    var modalNodes: [(identity: Identity, scope: [Identity])] = []
    var activeAccessibilityModal: [Identity]?
    var focusAncestors: [Identity?] = []
    var focusSourceOwners: [Identity: Identity] = [:]
    var anchoredFocusStarts: [Identity: Int] = [:]
    var anchoredFocusGroups: [(anchor: Identity, identities: [Identity])] = []

    walk(
      placed,
      hitTestOrder: &hitTestOrder,
      preVisit: { node, context, order, nextHitTestOrder in
        let interactionStart = interactionRegions.count
        let focusStart = focusRegions.count
        defer {
          let owner =
            focusRegions[focusStart...].first { $0.identity == node.identity }?.identity
            ?? focusAncestors.last.flatMap { $0 }
          focusAncestors.append(owner)
          focusSourceOwners[node.identity] = owner
          constrainInteractions(&interactionRegions, from: interactionStart, context: context)
        }
        if node.layoutMetadata.focusOrderAnchor != nil {
          anchoredFocusStarts[node.identity] = focusRegions.count
        }
        let scopePath = context.scopePath
        let sectionIdentity = context.sectionIdentity
        let modalFocusScopePath = context.modalFocusScopePath
        if let path = modalFocusScopePath {
          modalNodes.append((node.identity, path))
          if path.count >= (activeAccessibilityModal?.count ?? 0) {
            activeAccessibilityModal = path
          }
        }
        let clipRect = context.clipRect
        if node.semanticMetadata.isParagraph,
          let rect = interactionRect(for: node, clippedTo: clipRect)
        {
          paragraphs.append(.init(identity: node.identity, rect: rect))
        }
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

        if !sealingParentOnChain {
          let navigator = node.semanticMetadata.accessibilityStructure?.collectionNavigation
          let review = node.semanticMetadata.hostedCollectionItem?.review
          if let identity = navigator?.identity ?? review?.identity,
            let rect = interactionRect(for: node, clippedTo: clipRect)
          {
            accessibilityActionRegions.append(
              FocusRegion(
                identity: identity, rect: rect, focusInteractions: .automatic,
                scopePath: scopePath, sectionIdentity: sectionIdentity,
                modalFocusScopePath: modalFocusScopePath,
                ownerNodeID: review?.ownerNodeID ?? node.viewNodeID, ownerIdentity: node.identity))
          }
        }

        if let selection = node.semanticMetadata.hostedCollectionItem?.selection,
          interactionsEnabled, !sealingParentOnChain,
          let rect = interactionRect(for: node, clippedTo: clipRect)
        {
          accessibilityActionRegions.append(
            FocusRegion(
              identity: selection.actionIdentity, rect: rect, focusInteractions: .activate,
              scopePath: scopePath, sectionIdentity: sectionIdentity,
              modalFocusScopePath: modalFocusScopePath,
              ownerNodeID: selection.ownerNodeID, ownerIdentity: selection.actionIdentity))
        }

        if let tabs = node.semanticMetadata.accessibilityStructure?.tabs, !sealingParentOnChain {
          for tab in tabs {
            accessibilityActionRegions.append(
              FocusRegion(
                identity: tab.identity, rect: semanticBounds(for: node),
                focusInteractions: .activate,
                scopePath: scopePath, sectionIdentity: sectionIdentity,
                modalFocusScopePath: modalFocusScopePath,
                ownerNodeID: node.viewNodeID, ownerIdentity: node.identity))
          }
        }

        // Assistive operations have their own scope, independent of the role
        // and keyboard traversal. Runtime dispatch still checks enabled state,
        // read-only policy, owner currency, and the active modal boundary.
        if node.semanticMetadata.accessibilityControl?.actions.isEmpty == false,
          // Ordinary keyboard targets already publish this owner and scope.
          // Static/custom-role and disabled controls need an assistive route.
          !participatesInTopLevelFocus || !interactionsEnabled,
          !sealingParentOnChain
        {
          accessibilityActionRegions.append(
            FocusRegion(
              identity: node.identity, rect: semanticBounds(for: node),
              focusInteractions: .automatic, scopePath: scopePath, sectionIdentity: sectionIdentity,
              modalFocusScopePath: modalFocusScopePath,
              ownerNodeID: node.viewNodeID, ownerIdentity: node.identity))
        }

        if node.semanticMetadata.accessibilityStructure?.isVirtual == true {
          guard interactionsEnabled, !sealingParentOnChain else { return }
          if participatesInTopLevelFocus {
            accessibilityActionRegions.append(
              FocusRegion(
                identity: node.identity, rect: semanticBounds(for: node),
                focusInteractions: node.semanticMetadata.focusInteractions,
                scopePath: scopePath, sectionIdentity: sectionIdentity,
                modalFocusScopePath: modalFocusScopePath,
                ownerNodeID: node.viewNodeID, ownerIdentity: node.identity))
          }
          var ignoredPointerRegions: [InteractionRegion] = []
          appendPayloadSemantics(
            for: node, scopePath: scopePath, sectionIdentity: sectionIdentity,
            modalFocusScopePath: modalFocusScopePath, clippedTo: clipRect,
            sealingParentOnChain: false, allowsPointerHitTesting: false,
            interactionRegions: &ignoredPointerRegions,
            focusRegions: &accessibilityActionRegions, nextHitTestOrder: &nextHitTestOrder)
          return
        }

        if isEnabled, let space = node.semanticMetadata.namedCoordinateSpace {
          namedCoordinateSpaces[space] = node.bounds
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

        let focusEnabled =
          interactionsEnabled
          || (node.semanticMetadata.allowsFocusWhenDisabled
            && !interactionsDisabledOnChain
            && node.semanticMetadata.interactionAvailability.isEnabled)
        if participatesInTopLevelFocus, focusEnabled, !sealingParentOnChain {
          focusRegions.append(
            FocusRegion(
              identity: node.identity,
              rect: semanticBounds(for: node),
              focusInteractions: node.semanticMetadata.focusInteractions,
              scopePath: scopePath,
              sectionIdentity: sectionIdentity,
              modalFocusScopePath: modalFocusScopePath,
              ownerNodeID: node.viewNodeID,
              ownerIdentity: node.identity,
              collectionFocusTarget: node.semanticMetadata.hostedCollectionContainer?.focusTarget
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
                contentShape: explicitPath,
                pointerGesturePriority: node.semanticMetadata.pointerGesturePriority
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

        if let scrollRole = node.semanticMetadata.scrollRole {
          var route = ScrollRoute(
            identity: node.identity,
            viewNodeID: node.viewNodeID,
            viewportRect: node.scrollViewportRect ?? node.bounds,
            contentBounds: node.contentBounds,
            structuralHostChain: context.structuralHostChain
          )
          route.reducesMotion = node.environmentSnapshot.style.renderingReduceMotion
          route.scrollAnchorCorrection =
            node.children.first?.placementMetadata.scrollAnchorCorrection
          route.collectionScrollPosition =
            node.hostedTableVisibleLayout?.scrollPosition
            ?? node.hostedListVisibleLayout?.scrollPosition
          route.collectionMaximumAnchorRow =
            node.hostedTableVisibleLayout?.maximumAnchorRow
            ?? node.hostedListVisibleLayout?.maximumAnchorRow
          route.collectionScrollLayout =
            node.hostedTableVisibleLayout?.scrollMetadata?.navigation
            ?? node.hostedListVisibleLayout?.scrollMetadata?.navigation
          route.collectionInteractionRows =
            node.semanticMetadata.hostedCollectionContainer?.interactionRows
          // A disabled scroll view still answers programmatic commands; only
          // interactive input honours `.disabled` (STUI-1317).
          programmaticScrollRoutes.append(route)
          if interactionsEnabled {
            scrollRoutes.append(route)
            selectionRoutes.append(
              SelectionRoute(identity: node.identity, role: scrollRole)
            )
          }
        }
      },
      postVisit: { node, context, nextHitTestOrder in
        defer { _ = focusAncestors.popLast() }
        let interactionStart = interactionRegions.count
        defer {
          constrainInteractions(&interactionRegions, from: interactionStart, context: context)
        }
        defer {
          if let anchor = node.layoutMetadata.focusOrderAnchor,
            let start = anchoredFocusStarts.removeValue(forKey: node.identity)
          {
            anchoredFocusGroups.append((anchor, focusRegions[start...].map(\.identity)))
          }
        }
        guard node.semanticMetadata.accessibilityStructure?.isVirtual != true else { return }
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

    for group in anchoredFocusGroups {
      let anchor = focusSourceOwners[group.anchor] ?? group.anchor
      let members = Set(group.identities)
      let inserted = focusRegions.filter { members.contains($0.identity) }
      guard !inserted.isEmpty, !members.contains(anchor),
        focusRegions.contains(where: { $0.identity == anchor || $0.ownerIdentity == anchor })
      else { continue }
      focusRegions.removeAll { members.contains($0.identity) }
      if let index = focusRegions.lastIndex(where: {
        $0.identity == anchor || $0.ownerIdentity == anchor
      }) {
        focusRegions.insert(contentsOf: inserted, at: index + 1)
      }
    }
    let activeCommandScopePath = resolveActiveCommandScopePath(from: commandHostScopePaths)

    let scrollTargets = scrollTargets(from: placed)
    let accessibilityExtraction = accessibilityNodesAndVisualLabelRoutes(
      from: placed,
      focusRegions: focusRegions + accessibilityActionRegions,
      modalScopeIdentities: activeAccessibilityModal.map { active in
        Set(modalNodes.filter { $0.scope == active }.map(\.identity))
      }
    )
    let accessibilityWarnings =
      extractsAccessibilityWarnings
      ? accessibilityWarnings(
        from: placed,
        visualLabelRoutes: accessibilityExtraction.visualLabelRoutes
      ) : []

    var snapshot = SemanticSnapshot(
      interactionRegions: interactionRegions,
      focusRegions: focusRegions,
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets,
      selectionRoutes: selectionRoutes,
      namedCoordinateSpaces: namedCoordinateSpaces,
      accessibilityNodes: accessibilityExtraction.nodes,
      accessibilityWarnings: accessibilityWarnings,
      activeCommandScopePath: activeCommandScopePath
    )
    snapshot.activeModalScopePath = activeAccessibilityModal
    snapshot.mountedModalScopePaths = Set(modalNodes.map(\.scope))
    snapshot.paragraphs = paragraphs
    snapshot.accessibilityActionRegions = accessibilityActionRegions
    snapshot.programmaticScrollRoutes = programmaticScrollRoutes
    return snapshot
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
    var pointerClipRect: CellRect? = nil
    var pointerClipPaths: [Path] = []
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
          isModalPresentationScope(frame.node.semanticMetadata)
          ? nodeScopePath
          : frame.context.modalFocusScopePath
        let nodeClipRect = combinedClipRect(
          inherited: frame.context.clipRect,
          next: frame.node.clipBounds
        )
        let constrainsChildren = frame.node.layoutMetadata.constrainsDescendantPointerTargets
        let explicitPath =
          constrainsChildren
          ? transformedExplicitInteractionPath(for: frame.node) : nil
        let ownPointerClip: CellRect? =
          if !constrainsChildren {
            nil
          } else if let explicitPath {
            interactionRect(for: explicitPath, clippedTo: nodeClipRect)
              ?? .init(origin: .zero, size: .zero)
          } else {
            transformedExplicitInteractionRect(for: frame.node)
          }
        let pointerClip = combinedClipRect(
          inherited: frame.context.pointerClipRect, next: ownPointerClip)
        let pointerPaths = frame.context.pointerClipPaths + (explicitPath.map { [$0] } ?? [])
        let nodeContext = VisitContext(
          scopePath: nodeScopePath,
          sectionIdentity: nodeSectionIdentity,
          modalFocusScopePath: nodeModalFocusScopePath,
          clipRect: nodeClipRect,
          pointerClipRect: pointerClip, pointerClipPaths: pointerPaths,
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

        let contentClip = frame.node.drawMetadata.scrollIndicatorAppearance.map {
          frame.node.scrollViewportRect ?? $0.insetBounds(frame.node.bounds)
        }
        let childContext = VisitContext(
          scopePath: nodeScopePath,
          sectionIdentity: nodeSectionIdentity,
          modalFocusScopePath: nodeModalFocusScopePath,
          clipRect: combinedClipRect(inherited: nodeClipRect, next: contentClip),
          pointerClipRect: pointerClip, pointerClipPaths: pointerPaths,
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
      inherited.intersection(next) ?? .init(origin: .zero, size: .zero)
    }
  }

  /// Applies one inherited constraint path to every route a primitive emits,
  /// including synthetic rows, indicators and gestures. Keyboard focus does
  /// not use pointer content shapes.
  private func constrainInteractions(
    _ regions: inout [InteractionRegion], from start: Int, context: VisitContext
  ) {
    guard context.pointerClipRect != nil || !context.pointerClipPaths.isEmpty else { return }
    var index = start
    while index < regions.count {
      // Empty regions veto ancestor-action fallback for keyboard-only actions.
      // Their presence remains meaningful even though they cannot be clicked.
      if let clip = context.pointerClipRect, !regions[index].rect.isEmpty {
        guard let rect = regions[index].rect.intersection(clip) else {
          regions.remove(at: index)
          continue
        }
        regions[index].rect = rect
      }
      regions[index].ancestorContentShapes = context.pointerClipPaths
      index += 1
    }
  }

  private func isModalPresentationScope(
    _ metadata: SemanticMetadata
  ) -> Bool {
    switch metadata.accessibilityRole {
    case .alert, .confirmationDialog, .sheet:
      true
    case .popover:
      // Interactive popovers create a scope; read-only tips do not. Keep
      // return-focus bookkeeping aligned with that presentation policy.
      metadata.focusScopeBoundary
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
              rect: estimate.rect,
              role: .lazyElement
            )
          )
          targets[targets.count - 1].isEstimated = estimate.isEstimated
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
    // A scroll body's hit target is its content viewport. Indicator tracks
    // have separate routes, and the direct-pan guard compares this target
    // with the published scroll viewport to distinguish an inner control.
    // Lists and tables publish a viewport too, for their scroll routes, but
    // their border ring has no route of its own: a wheel or press there
    // belongs to the collection, so their hit target stays the full bounds.
    let semanticBounds =
      node.drawMetadata.scrollIndicatorAppearance != nil
      ? node.scrollViewportRect ?? semanticBounds(for: node)
      : semanticBounds(for: node)
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

    guard let minX = Int(exactly: bounds.origin.x.rounded(.down)),
      let minY = Int(exactly: bounds.origin.y.rounded(.down)),
      let maxX = Int(exactly: bounds.maxX.rounded(.up)),
      let maxY = Int(exactly: bounds.maxY.rounded(.up))
    else { return nil }
    let (width, widthOverflow) = maxX.subtractingReportingOverflow(minX)
    let (height, heightOverflow) = maxY.subtractingReportingOverflow(minY)
    guard !widthOverflow, !heightOverflow else { return nil }
    let rect = CellRect(
      origin: CellPoint(x: minX, y: minY),
      size: CellSize(width: width, height: height)
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
        x: SaturatingConversion.adding(rect.origin.x, delta.x),
        y: SaturatingConversion.adding(rect.origin.y, delta.y)
      ),
      size: rect.size
    )
  }
}
