package struct ScrollOffset: Equatable, Sendable {
  package var x: Int
  package var y: Int

  package init(
    x: Int = 0,
    y: Int = 0
  ) {
    self.x = x
    self.y = y
  }

  package static let zero = Self()
}

package struct ScrollPositionRegistrationSnapshot {
  package var identity: Identity
  package var ownerViewNodeID: ViewNodeID?
  package var axes: AxisSet
  /// Resolve-time value guards commit normalization against a newer input.
  package var resolvedOffset: ScrollOffset?
  /// An offset correction applied by this registration's committed frame, not authored input.
  package var committedOffsetCorrection: (requested: ScrollOffset, corrected: ScrollOffset)? = nil
  package var currentOffset: @MainActor () -> ScrollOffset
  package var applyOffset: @MainActor (ScrollOffset) -> Void
  /// The logical collection position remains stable while estimated cell
  /// offsets change. It also detects input that supersedes a pending command.
  package var currentCollectionAnchor: @MainActor () -> CollectionScrollAnchor?
  /// The authored binding's source token, when its producer supplies one.
  /// Registrations rebuild every resolve pass, so "registration replaced"
  /// never means "binding replaced" — this token is the only currency that
  /// distinguishes a re-resolve of the same authored binding (token stable)
  /// from a rebind to a different one (token changes). Consumed by scroll
  /// momentum to retire a fling whose binding was swapped out from under
  /// it. Nil (raw closures carry no identity) disables the distinction.
  package var bindingSourceID: AnyID?
  /// Reveals a collection row, including rows outside the placed window whose
  /// identities would cost O(dataset) to publish eagerly. The same calculation
  /// handles placed rows so their measured height and usable viewport agree.
  /// The producer performs the move itself and reports whether
  /// anything changed, because a collection's usable window is smaller than
  /// its raw viewport rect (overflow indicators, fixed table chrome), so the
  /// offset arithmetic here cannot express the right answer for it. Returns
  /// nil when the query matches nothing. Ordinary `ScrollView` uses cell
  /// geometry below, including allocation targets for its unrealized lazy rows.
  package var revealTarget: (@MainActor (ScrollTargetQuery, UnitPoint?) -> Bool?)?
  /// Scrolls to an edge of content this route owns, reporting whether anything
  /// moved. A viewport-backed collection answers edges itself for the same
  /// reason it answers ``revealTarget``: its line model is not the cell
  /// arithmetic below, and rows that render taller than one cell make the
  /// route's content rect an estimate. Absent for every `ScrollView`.
  package var scrollToEdge: (@MainActor (Edge) -> Bool)?

  package init(
    identity: Identity,
    ownerViewNodeID: ViewNodeID? = nil,
    axes: AxisSet = [.horizontal, .vertical],
    resolvedOffset: ScrollOffset? = nil,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void,
    bindingSourceID: AnyID? = nil,
    currentCollectionAnchor: @escaping @MainActor () -> CollectionScrollAnchor? = { nil },
    revealTarget: (@MainActor (ScrollTargetQuery, UnitPoint?) -> Bool?)? = nil,
    scrollToEdge: (@MainActor (Edge) -> Bool)? = nil
  ) {
    self.identity = identity
    self.ownerViewNodeID = ownerViewNodeID
    self.axes = axes
    self.resolvedOffset = resolvedOffset
    self.currentOffset = currentOffset
    self.applyOffset = applyOffset
    self.currentCollectionAnchor = currentCollectionAnchor
    self.bindingSourceID = bindingSourceID
    self.revealTarget = revealTarget
    self.scrollToEdge = scrollToEdge
  }
}

@MainActor
package final class LocalScrollPositionRegistry: Equatable {
  private var registrations: [Identity: ScrollPositionRegistrationSnapshot] = [:]
  private var latestScrollRoutes: [ScrollRoute] = []
  private var latestScrollTargets: [ScrollTarget] = []
  private struct PendingLazyTarget {
    var query: ScrollTargetQuery
    var anchor: UnitPoint?
    var originalOffset: ScrollOffset
    var requestedOffset: ScrollOffset
  }
  private var pendingLazyTargets: [Identity: PendingLazyTarget] = [:]
  private struct PendingCollectionTarget {
    let query: ScrollTargetQuery
    let anchor: UnitPoint?
    let requestedAnchor: CollectionScrollAnchor
  }
  private var pendingCollectionTargets: [Identity: PendingCollectionTarget] = [:]
  /// Far-edge commands resolved against the extent the previous frame
  /// measured. Lazy stacks estimate unrealized rows, and the action that
  /// issued the command may also have changed the content, so the frame that
  /// lays out the edge can grow or shrink the extent; the command is
  /// re-resolved once that frame publishes its routes (see `sync`). A route
  /// owes at most one far edge per axis: bottom (`vertical`) and trailing
  /// (`horizontal`) are independent, and top or leading cancels only its own
  /// axis (STUI-1263).
  private struct PendingFarEdge {
    var axes: AxisSet
    var requestedOffset: ScrollOffset
    var remainingRefinements: Int
  }
  private var pendingFarEdges: [Identity: PendingFarEdge] = [:]
  /// Bounds re-resolution for content whose extent depends on its own offset.
  private static let farEdgeRefinementLimit = 4
  /// A `scrollTo(_:anchor:)` that matched nothing the previous frame placed
  /// or a collection answered for. The action that issued it may have
  /// inserted its target, so the next sync retries it once against that
  /// frame's targets and registrations (STUI-1306). Keyed by the reader
  /// scope, in issue order; a later command from the same scope replaces it.
  private struct PendingUnresolvedTarget {
    let scopeIdentity: Identity?
    let query: ScrollTargetQuery
    let anchor: UnitPoint?
    /// The scope's first route and its offset when the command was issued.
    /// Input that moves that route before the retry supersedes the command.
    let routeIdentity: Identity?
    let routeOffset: ScrollOffset?
  }
  private var pendingUnresolvedTargets: [PendingUnresolvedTarget] = []
  /// Requests the frame whose sync resolves a deferred command: a far edge
  /// that moved nothing against the previous extent, or an unresolved target.
  /// The run loop installs its scheduler. Without a frame such a command
  /// would wait for an unrelated later frame and then apply there.
  package weak var deferredCommandInvalidator: (any Invalidating)?
  /// What each scroll route last auto-revealed (focused element + text cursor),
  /// keyed by the route identity. Lets `sync` reveal changed focus or cursor
  /// instead of enforcing a standing per-frame constraint
  /// that would fight user-initiated wheel/drag scrolling.
  ///
  /// This is interaction session state, deliberately decoupled from the
  /// registration lifecycle: the run loop churns `reset()` (full republication)
  /// and `removeSubtrees()` (scoped republication) on essentially every frame to
  /// re-publish the offset closures, so this map must NOT be cleared by either —
  /// doing so re-fires focus-reveal every frame and reintroduces the stall. It
  /// is bounded by the live route set and pruned when focus or a route departs.
  private var lastRevealAnchors: [Identity: ScrollRevealAnchor] = [:]

  /// Last synchronized offsets distinguish layout changes from deliberate scroll input.
  private struct SyncedPosition {
    let offset: ScrollOffset
    let bindingSourceID: AnyID?
  }
  private var lastSyncedPositions: [Identity: SyncedPosition] = [:]
  /// A supported command is intentional even when its requested offset is already current.
  /// Keep it through registration republication and target refinement, then consume it in sync.
  private var pendingExplicitScrollRoutes: Set<Identity> = []

  package init() {}

  /// How many scroll routes currently hold a focus-reveal anchor.
  ///
  /// Exposed for stress harnesses that assert `sync` prunes anchors for routes
  /// that are no longer live. Reading the count through a declared member keeps
  /// a rename of the underlying storage a compile error.
  package var revealAnchorCount: Int {
    lastRevealAnchors.count
  }

  nonisolated package static func == (
    lhs: LocalScrollPositionRegistry,
    rhs: LocalScrollPositionRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    axes: AxisSet = [.horizontal, .vertical],
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void,
    bindingSourceID: AnyID? = nil,
    currentCollectionAnchor: @escaping @MainActor () -> CollectionScrollAnchor? = { nil },
    revealTarget: (@MainActor (ScrollTargetQuery, UnitPoint?) -> Bool?)? = nil,
    scrollToEdge: (@MainActor (Edge) -> Bool)? = nil
  ) {
    let registration = ScrollPositionRegistrationSnapshot(
      identity: identity,
      ownerViewNodeID: ViewNodeContext.current?.viewNodeID,
      axes: axes, resolvedOffset: currentOffset(),
      currentOffset: currentOffset,
      applyOffset: applyOffset,
      bindingSourceID: bindingSourceID,
      currentCollectionAnchor: currentCollectionAnchor,
      revealTarget: revealTarget,
      scrollToEdge: scrollToEdge
    )
    registrations[identity] = registration
    ViewNodeContext.current?.recordScrollPositionRegistration(registration)
  }

  /// The registered binding's source token for `identity`, when its producer
  /// supplied one (see ``ScrollPositionRegistrationSnapshot/bindingSourceID``).
  package func bindingSourceID(for identity: Identity) -> AnyID? {
    registrations[identity]?.bindingSourceID
  }

  package func updateGeometry(
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget]
  ) {
    latestScrollRoutes = scrollRoutes
    latestScrollTargets = scrollTargets
  }

  /// Preserve a focused collection row when changed row heights or viewport size hide it.
  /// A new scroll request takes precedence over this correction.
  package func revealCollectionFocusAfterResize(
    _ focusedRegion: FocusRegion,
    currentFocusedRegion: FocusRegion? = nil,
    previousRoutes: [ScrollRoute],
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget]
  ) -> Bool {
    guard let owner = focusedRegion.ownerIdentity,
      let ownerNodeID = focusedRegion.ownerNodeID,
      !pendingExplicitScrollRoutes.contains(owner),
      let registration = registrations[owner],
      registration.ownerViewNodeID == ownerNodeID,
      let previous = previousRoutes.first(where: { $0.identity == owner }),
      let route = scrollRoutes.first(where: { $0.identity == owner }),
      let previousLayout = previous.collectionScrollLayout,
      let layout = route.collectionScrollLayout,
      previousLayout.anchor == layout.anchor,
      registration.currentCollectionAnchor() == previousLayout.anchor
    else { return false }

    let viewportSizeChanged = previous.viewportRect.size != route.viewportRect.size
    let usableHeightChanged = previousLayout.visibleLines.count != layout.visibleLines.count
    let hasSameRowCount = previousLayout.geometry.rowCount == layout.geometry.rowCount
    let canValidateItem = focusedRegion.collectionFocusTarget != nil
    let rowGeometryChanged =
      (hasSameRowCount || canValidateItem) && previousLayout.geometry != layout.geometry
    guard viewportSizeChanged || usableHeightChanged || rowGeometryChanged else { return false }

    var target = focusedRegion.collectionFocusTarget
    if let currentFocusedRegion {
      // A table keeps container focus when its selected row leaves the window.
      // Recover only the same, previously visible item; wheel scrolling away
      // from selection and authored selection changes are not focus recovery.
      guard focusedRegion.identity == owner,
        let previousTarget = target,
        let currentTarget = currentFocusedRegion.collectionFocusTarget,
        previousTarget.itemIdentity == currentTarget.itemIdentity,
        collectionTargetIsVisible(previousTarget, in: previousLayout),
        !collectionTargetIsVisible(currentTarget, in: layout)
      else { return false }
      target = currentTarget
    }
    var query = ScrollTargetQuery(identity: target?.itemIdentity ?? focusedRegion.identity)
    query.expectedCollectionRowIndex = target?.rowIndex
    updateGeometry(scrollRoutes: scrollRoutes, scrollTargets: scrollTargets)
    return registration.revealTarget?(query, nil) == true
  }

  private func collectionTargetIsVisible(
    _ target: CollectionFocusTarget, in layout: CollectionScrollLayout
  ) -> Bool {
    guard target.rowIndex >= 0, target.rowIndex < layout.geometry.rowCount,
      !layout.visibleLines.isEmpty
    else { return false }
    let row = layout.geometry.lineRange(forRow: target.rowIndex)
    let leadingEnd = row.lowerBound + min(row.count, layout.visibleLines.count)
    return row.lowerBound >= layout.visibleLines.lowerBound
      && leadingEnd <= layout.visibleLines.upperBound
  }

  /// Recover only a previously visible target that still belongs to the same scroll owner.
  /// Lazy allocation targets let the existing eager rerender realize its row without
  /// making other offscreen controls participate in focus traversal.
  package func revealFocusAfterGeometryChange(
    _ focusedRegion: FocusRegion,
    previousRoutes: [ScrollRoute],
    previousTargets: [ScrollTarget],
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget],
    focusRegions: [FocusRegion]
  ) -> Bool {
    if let currentRegion = focusRegions.first(where: { $0.identity == focusedRegion.identity }),
      currentRegion.ownerNodeID != focusedRegion.ownerNodeID
    {
      return false
    }
    guard
      let previousTarget = previousTargets.first(where: {
        $0.identity == focusedRegion.identity
      })
    else { return false }
    let previousChain = containingRoutes(
      startingAt: previousTarget.scrollIdentity, routes: previousRoutes, targets: previousTargets)
    guard !previousChain.isEmpty else { return false }
    var visibleRect: CellRect? = previousTarget.rect
    for route in previousChain {
      visibleRect = visibleRect?.intersection(route.viewportRect)
    }
    // A target hidden by an inner viewport is not visible merely because its
    // unclipped rectangle intersects a larger outer viewport.
    guard visibleRect != nil else { return false }

    let currentTarget: (rect: CellRect, scrollIdentity: Identity)
    if let target = scrollTargets.first(where: { $0.identity == focusedRegion.identity }) {
      currentTarget = (target.rect, target.scrollIdentity)
    } else {
      // A surviving allocation row permits one speculative realization. It
      // cannot establish that the focused descendant still exists afterward.
      let lazyTarget = scrollTargets.filter {
        $0.role == .lazyElement && focusedRegion.identity.isDescendant(of: $0.identity)
      }.max { $0.identity.components.count < $1.identity.components.count }
      guard let lazyTarget,
        let previousAncestor = previousTargets.first(where: {
          $0.scrollIdentity == lazyTarget.scrollIdentity && $0.identity == lazyTarget.identity
        })
      else { return false }
      let rect = CellRect(
        origin: CellPoint(
          x: lazyTarget.rect.origin.x + previousTarget.rect.origin.x
            - previousAncestor.rect.origin.x,
          y: lazyTarget.rect.origin.y + previousTarget.rect.origin.y
            - previousAncestor.rect.origin.y),
        size: previousTarget.rect.size)
      currentTarget = (rect, lazyTarget.scrollIdentity)
    }
    let currentChain = containingRoutes(
      startingAt: currentTarget.scrollIdentity, routes: scrollRoutes, targets: scrollTargets)
    guard !currentChain.isEmpty else { return false }
    var routePairs:
      [(
        route: ScrollRoute, previous: ScrollRoute,
        registration: ScrollPositionRegistrationSnapshot, position: SyncedPosition
      )] = []
    // Validate the whole chain before changing any offset. A deliberate scroll
    // or replaced owner at any containing viewport takes precedence throughout.
    for route in currentChain {
      guard let previous = previousChain.first(where: { $0.identity == route.identity }),
        let ownerNodeID = previous.viewNodeID, route.viewNodeID == ownerNodeID,
        let registration = registrations[route.identity],
        registration.ownerViewNodeID == ownerNodeID,
        let position = lastSyncedPositions[route.identity],
        !hasNewScrollInput(in: route, registration: registration)
      else { return false }
      if let previousLayout = previous.collectionScrollLayout,
        registration.currentCollectionAnchor() != previousLayout.anchor
      {
        return false
      }
      routePairs.append((route, previous, registration, position))
    }

    var changed = false
    var projectedRect = currentTarget.rect
    var previousDescendantOffset = ScrollOffset.zero
    var currentDescendantOffset = ScrollOffset.zero
    for pair in routePairs {
      let route = pair.route
      let registration = pair.registration
      let preservesProducerOffset = registration.revealTarget != nil
      let previousOffset = layoutOffset(
        pair.position.offset, in: pair.previous, preservesProducerOffset: preservesProducerOffset)
      let currentOffset = registration.currentOffset()
      let placedOffset = layoutOffset(
        currentOffset, in: route, preservesProducerOffset: preservesProducerOffset)
      let previousContentRect = contentRect(
        previousTarget.rect, in: pair.previous, descendantOffset: previousDescendantOffset)
      let currentContentRect = contentRect(
        projectedRect, in: route, descendantOffset: currentDescendantOffset)
      let viewportSizeChanged = pair.previous.viewportRect.size != route.viewportRect.size
      let targetGeometryChanged = previousContentRect != currentContentRect
      var nextOffset = placedOffset
      if route.collectionScrollLayout == nil, viewportSizeChanged || targetGeometryChanged {
        nextOffset = adjustedOffset(
          currentOffset, revealing: projectedRect, in: route, preservesProducerOffset: false)
        if nextOffset != currentOffset {
          registration.applyOffset(nextOffset)
          projectedRect = CellRect(
            origin: CellPoint(
              x: projectedRect.origin.x - (nextOffset.x - placedOffset.x),
              y: projectedRect.origin.y - (nextOffset.y - placedOffset.y)),
            size: projectedRect.size)
          changed = true
        }
      }
      previousDescendantOffset = ScrollOffset(
        x: previousDescendantOffset.x + previousOffset.x,
        y: previousDescendantOffset.y + previousOffset.y)
      currentDescendantOffset = ScrollOffset(
        x: currentDescendantOffset.x + nextOffset.x,
        y: currentDescendantOffset.y + nextOffset.y)
    }
    return changed
  }

  /// Commit geometry corrections only for the request this frame resolved.
  /// Measurement and abandoned worker candidates never write authored bindings.
  package func commitScrollOffsets(_ routes: [ScrollRoute]) {
    for route in routes {
      guard let registration = registrations[route.identity] else { continue }
      registrations[route.identity]?.committedOffsetCorrection = nil
      let current = registration.currentOffset()
      let corrected: ScrollOffset
      if let correction = route.scrollAnchorCorrection {
        let requested = ScrollOffset(
          x: correction.requestedOffset.x, y: correction.requestedOffset.y)
        guard current == requested else { continue }
        corrected = ScrollOffset(
          x: correction.correctedOffset.x, y: correction.correctedOffset.y)
      } else if registration.revealTarget == nil, registration.resolvedOffset == current {
        corrected = clampedOffset(current, in: route)
      } else {
        continue
      }
      guard current != corrected else { continue }
      registrations[route.identity]?.committedOffsetCorrection = (current, corrected)
      registration.applyOffset(corrected)
    }
  }

  /// Returns copies of `routes` with `contentOffset` populated from each
  /// region's live scroll offset. Routes without a live registration are
  /// returned unchanged (keeping their `.zero` offset).
  ///
  /// Used at the web-host presentation boundary to publish scroll extents for
  /// scroll-chaining; see `docs/proposals/EMBEDDED_WEB_SCROLL_CHAINING.md` in
  /// the coordination root.
  package func routesWithCurrentOffsets(
    _ routes: [ScrollRoute]
  ) -> [ScrollRoute] {
    routes.map { route in
      guard let registration = registrations[route.identity] else {
        return route
      }
      let current = registration.currentOffset()
      let offset = registration.revealTarget == nil ? clampedOffset(current, in: route) : current
      var enriched = route
      enriched.contentOffset = CellPoint(x: offset.x, y: offset.y)
      if let position = route.collectionScrollPosition {
        let maximum = max(0, route.contentBounds.size.height - route.viewportRect.size.height)
        // Chaining follows the measured window's endpoints. The body scrolls
        // by whole rows, while chrome and indicators stay fixed in the viewport.
        enriched.contentOffset.y =
          position.isAtStart
          ? 0
          : position.isAtEnd ? maximum : min(maximum, max(0, position.cellOffset))
      }
      return enriched
    }
  }

  @discardableResult
  package func scrollToTarget(
    _ query: ScrollTargetQuery,
    anchor: UnitPoint?,
    scopeIdentity: Identity?
  ) -> Bool {
    removePendingUnresolvedTarget(scopeIdentity: scopeIdentity)
    if let handled = resolveScrollTarget(query, anchor: anchor, scopeIdentity: scopeIdentity) {
      return handled
    }
    // Nothing the previous frame placed, and no collection, matches. The
    // action may have inserted the target: retry after the next layout.
    let route = firstRoute(matching: scopeIdentity)
    pendingUnresolvedTargets.append(
      PendingUnresolvedTarget(
        scopeIdentity: scopeIdentity, query: query, anchor: anchor,
        routeIdentity: route?.identity,
        routeOffset: route.flatMap { registrations[$0.identity]?.currentOffset() }))
    requestDeferredCommandFrame(for: route?.identity ?? scopeIdentity)
    return false
  }

  /// Resolves a target command against the latest published frame. Returns
  /// nil when no placed target and no collection matches the query.
  private func resolveScrollTarget(
    _ query: ScrollTargetQuery,
    anchor: UnitPoint?,
    scopeIdentity: Identity?
  ) -> Bool? {
    if let target = firstTarget(matching: query, scopeIdentity: scopeIdentity),
      let route = latestScrollRoutes.first(where: { $0.identity == target.scrollIdentity }),
      let registration = registrations[target.scrollIdentity]
    {
      pendingExplicitScrollRoutes.insert(route.identity)
      // A later command on a route replaces its pending far edge.
      pendingFarEdges.removeValue(forKey: route.identity)
      if let handled = registration.revealTarget?(query, anchor) {
        recordCollectionTarget(query, anchor: anchor, registration: registration, changed: handled)
        return handled
      }
      let original = registration.currentOffset()
      // The target's rect is where the last published frame placed it, at
      // the offset that frame laid out. An earlier command of the same
      // action may already have moved the offset, so the rect is first
      // carried to the current offset; the commands then compose in order.
      let changed = scrollTo(
        rect: target.rect,
        anchor: anchor,
        route: route,
        registration: registration,
        placedAt: lastSyncedPositions[route.identity]?.offset
      )
      if target.isEstimated {
        pendingLazyTargets[route.identity] = .init(
          query: query, anchor: anchor,
          originalOffset: original, requestedOffset: registration.currentOffset())
      } else {
        pendingLazyTargets.removeValue(forKey: route.identity)
      }
      return changed
    }

    // No placed target: ask the in-scope producers that answer for their own
    // unplaced rows (viewport-backed collections).
    for route in latestScrollRoutes.reversed()
    where routeMatchesScope(route.identity, scopeIdentity: scopeIdentity)
      || hostChainMatchesScope(route, scopeIdentity: scopeIdentity)
    {
      guard let registration = registrations[route.identity],
        let handled = registration.revealTarget?(query, anchor)
      else {
        continue
      }
      pendingExplicitScrollRoutes.insert(route.identity)
      pendingFarEdges.removeValue(forKey: route.identity)
      recordCollectionTarget(query, anchor: anchor, registration: registration, changed: handled)
      return handled
    }
    return nil
  }

  /// A relative or absolute command replaces every command still pending on
  /// its route and scope: the later command wins.
  private func supersedePendingCommands(on identity: Identity, scopeIdentity: Identity?) {
    removePendingUnresolvedTarget(scopeIdentity: scopeIdentity)
    pendingFarEdges.removeValue(forKey: identity)
    pendingLazyTargets.removeValue(forKey: identity)
    pendingCollectionTargets.removeValue(forKey: identity)
  }

  private func removePendingUnresolvedTarget(scopeIdentity: Identity?) {
    guard !pendingUnresolvedTargets.isEmpty else { return }
    pendingUnresolvedTargets.removeAll { $0.scopeIdentity == scopeIdentity }
  }

  /// Retries each unresolved target once, against the frame this sync
  /// received. Input that moved the scope's route since the command
  /// supersedes it; a target that still matches nothing is dropped.
  private func retryUnresolvedTargets() -> Bool {
    guard !pendingUnresolvedTargets.isEmpty else { return false }
    let pending = pendingUnresolvedTargets
    pendingUnresolvedTargets.removeAll(keepingCapacity: true)
    var changed = false
    for command in pending {
      if let identity = command.routeIdentity, let offset = command.routeOffset,
        let registration = registrations[identity], registration.currentOffset() != offset
      {
        continue
      }
      if resolveScrollTarget(
        command.query, anchor: command.anchor, scopeIdentity: command.scopeIdentity)
        == true
      {
        changed = true
      }
    }
    return changed
  }

  /// See ``deferredCommandInvalidator``. A command issued while a view is
  /// being evaluated needs no request: the sync of the frame being built
  /// resolves it, and requesting another frame there would re-run the body
  /// that issued the command on every frame.
  private func requestDeferredCommandFrame(for identity: Identity?) {
    guard let identity, ViewNodeContext.current == nil else { return }
    deferredCommandInvalidator?.requestInvalidation(of: [identity])
  }

  private func recordCollectionTarget(
    _ query: ScrollTargetQuery,
    anchor: UnitPoint?,
    registration: ScrollPositionRegistrationSnapshot,
    changed: Bool
  ) {
    guard let requestedAnchor = registration.currentCollectionAnchor() else { return }
    let pending = pendingCollectionTargets.removeValue(forKey: registration.identity)
    // A second command can request the same estimated anchor before its frame
    // measures the target. It still needs refinement, even without a new write.
    guard changed || pending?.requestedAnchor == requestedAnchor else { return }
    pendingCollectionTargets[registration.identity] = PendingCollectionTarget(
      query: query, anchor: anchor, requestedAnchor: requestedAnchor)
  }

  /// Scrolls `route` so that `targetRect` meets `anchor`, and reports whether
  /// the offset moved. `placedOffset` is the offset of the frame that placed
  /// the rect, when it may differ from the current one.
  private func scrollTo(
    rect placedRect: CellRect,
    anchor: UnitPoint?,
    route: ScrollRoute,
    registration: ScrollPositionRegistrationSnapshot,
    placedAt placedOffset: ScrollOffset? = nil
  ) -> Bool {
    let currentOffset = registration.currentOffset()
    var targetRect = placedRect
    if let placedOffset {
      let producer = registration.revealTarget != nil
      let placed = layoutOffset(placedOffset, in: route, preservesProducerOffset: producer)
      let current = layoutOffset(currentOffset, in: route, preservesProducerOffset: producer)
      targetRect = CellRect(
        origin: CellPoint(
          x: SaturatingConversion.adding(placedRect.origin.x, placed.x - current.x),
          y: SaturatingConversion.adding(placedRect.origin.y, placed.y - current.y)),
        size: placedRect.size)
    }
    let adjustedOffset = adjustedOffset(
      currentOffset,
      scrolling: targetRect,
      anchor: anchor,
      in: route,
      preservesProducerOffset: registration.revealTarget != nil
    )
    guard adjustedOffset != currentOffset else {
      return false
    }

    registration.applyOffset(adjustedOffset)
    return true
  }

  @discardableResult
  package func scrollToEdge(
    _ edge: Edge,
    scopeIdentity: Identity?
  ) -> Bool {
    guard let route = firstRoute(matching: scopeIdentity),
      let registration = registrations[route.identity]
    else {
      return false
    }
    pendingExplicitScrollRoutes.insert(route.identity)
    removePendingUnresolvedTarget(scopeIdentity: scopeIdentity)
    // A later command on a route replaces its pending target refinements.
    pendingLazyTargets.removeValue(forKey: route.identity)
    pendingCollectionTargets.removeValue(forKey: route.identity)
    if let scrollToEdge = registration.scrollToEdge {
      return scrollToEdge(edge)
    }

    let currentOffset = registration.currentOffset()
    let next = edgeOffset(edge, from: currentOffset, in: route)
    recordFarEdge(edge, on: route.identity, axes: registration.axes, from: currentOffset, to: next)
    guard next != currentOffset else {
      // The previous extent puts the edge here, but the action that issued
      // the command may have grown the content (STUI-1305). The pending
      // edge re-resolves after the next layout, which this requests.
      if pendingFarEdges[route.identity] != nil {
        requestDeferredCommandFrame(for: route.identity)
      }
      return false
    }

    registration.applyOffset(next)
    return true
  }

  /// Records a far-edge command on its own axis, or cancels that axis for a
  /// near edge. A pending edge whose route has moved since its own command
  /// was superseded and does not carry over.
  private func recordFarEdge(
    _ edge: Edge, on identity: Identity, axes routeAxes: AxisSet,
    from currentOffset: ScrollOffset, to next: ScrollOffset
  ) {
    var pending = pendingFarEdges[identity].flatMap {
      $0.requestedOffset == currentOffset ? $0 : nil
    }
    let axis: AxisSet = edge == .top || edge == .bottom ? .vertical : .horizontal
    if edge == .bottom || edge == .trailing {
      if routeAxes.contains(axis) {
        pending =
          pending ?? PendingFarEdge(axes: [], requestedOffset: next, remainingRefinements: 0)
        pending?.axes.insert(axis)
      }
    } else {
      pending?.axes.remove(axis)
    }
    guard var pending, !pending.axes.isEmpty else {
      pendingFarEdges.removeValue(forKey: identity)
      return
    }
    pending.requestedOffset = next
    pending.remainingRefinements = Self.farEdgeRefinementLimit
    pendingFarEdges[identity] = pending
  }

  /// Refines every pending far edge whose route this frame published, and
  /// reports whether any offset moved. Pending edges of departed routes,
  /// superseded commands and exhausted or settled refinements are dropped.
  private func refineFarEdges(in scrollRoutes: [ScrollRoute]) -> Bool {
    guard !pendingFarEdges.isEmpty else { return false }
    var unvisited = Set(pendingFarEdges.keys)
    var refined = false
    for route in scrollRoutes where unvisited.remove(route.identity) != nil {
      let identity = route.identity
      guard let pending = pendingFarEdges[identity],
        let registration = registrations[identity],
        registration.currentOffset() == pending.requestedOffset,
        pending.remainingRefinements > 0
      else {
        pendingFarEdges.removeValue(forKey: identity)
        continue
      }
      var next = pending.requestedOffset
      if pending.axes.contains(.vertical) { next = edgeOffset(.bottom, from: next, in: route) }
      if pending.axes.contains(.horizontal) { next = edgeOffset(.trailing, from: next, in: route) }
      guard next != pending.requestedOffset else {
        pendingFarEdges.removeValue(forKey: identity)
        continue
      }
      pendingFarEdges[identity] = .init(
        axes: pending.axes, requestedOffset: next,
        remainingRefinements: pending.remainingRefinements - 1)
      registration.applyOffset(next)
      refined = true
    }
    for identity in unvisited {
      pendingFarEdges.removeValue(forKey: identity)
    }
    return refined
  }

  /// Refines each command's estimated lazy target against the materialized
  /// frame. Empty targets restore the pre-command viewport. A later input
  /// offset supersedes the command instead of being overwritten by it.
  private func refineLazyTargets(in scrollRoutes: [ScrollRoute]) -> Bool {
    guard !pendingLazyTargets.isEmpty else { return false }
    var unvisited = Set(pendingLazyTargets.keys)
    var refined = false
    for route in scrollRoutes where unvisited.remove(route.identity) != nil {
      let identity = route.identity
      guard let pending = pendingLazyTargets[identity],
        let registration = registrations[identity],
        registration.currentOffset() == pending.requestedOffset
      else {
        pendingLazyTargets.removeValue(forKey: identity)
        continue
      }
      let target = firstTarget(matching: pending.query, scopeIdentity: identity)
      guard target?.isEstimated != true else { continue }
      pendingLazyTargets.removeValue(forKey: identity)
      if let target {
        if scrollTo(
          rect: target.rect, anchor: pending.anchor, route: route,
          registration: registration)
        {
          refined = true
        }
      } else if registration.currentOffset() != pending.originalOffset {
        registration.applyOffset(pending.originalOffset)
        refined = true
      }
    }
    for identity in unvisited {
      pendingLazyTargets.removeValue(forKey: identity)
    }
    return refined
  }

  /// Refines a collection target once the requested window has been
  /// measured. Using its logical anchor avoids mistaking a height correction
  /// for new input.
  private func refineCollectionTargets(in scrollRoutes: [ScrollRoute]) -> Bool {
    guard !pendingCollectionTargets.isEmpty else { return false }
    var unvisited = Set(pendingCollectionTargets.keys)
    var refined = false
    for route in scrollRoutes where unvisited.remove(route.identity) != nil {
      let identity = route.identity
      guard let pending = pendingCollectionTargets[identity],
        let registration = registrations[identity],
        registration.currentCollectionAnchor() == pending.requestedAnchor
      else {
        pendingCollectionTargets.removeValue(forKey: identity)
        continue
      }
      guard route.collectionScrollLayout?.anchor == pending.requestedAnchor else { continue }
      pendingCollectionTargets.removeValue(forKey: identity)
      if registration.revealTarget?(pending.query, pending.anchor) == true { refined = true }
    }
    for identity in unvisited {
      pendingCollectionTargets.removeValue(forKey: identity)
    }
    return refined
  }

  private func edgeOffset(
    _ edge: Edge, from currentOffset: ScrollOffset, in route: ScrollRoute
  ) -> ScrollOffset {
    var next = currentOffset
    switch edge {
    case .top:
      next.y = 0
    case .bottom:
      next.y = max(0, route.contentBounds.size.height - route.viewportRect.size.height)
    case .leading:
      next.x = 0
    case .trailing:
      next.x = max(0, route.contentBounds.size.width - route.viewportRect.size.width)
    }
    return clampedOffset(next, in: route)
  }

  @discardableResult
  package func scrollBy(
    x deltaX: Int = 0,
    y deltaY: Int = 0,
    scopeIdentity: Identity?
  ) -> Bool {
    guard deltaX != 0 || deltaY != 0 else {
      return false
    }
    guard let route = firstRoute(matching: scopeIdentity),
      let registration = registrations[route.identity]
    else {
      return false
    }

    pendingExplicitScrollRoutes.insert(route.identity)
    supersedePendingCommands(on: route.identity, scopeIdentity: scopeIdentity)
    let currentOffset = registration.currentOffset()
    let next = clampedOffset(
      ScrollOffset(
        x: SaturatingConversion.adding(currentOffset.x, deltaX),
        y: SaturatingConversion.adding(currentOffset.y, deltaY)),
      in: route
    )
    guard next != currentOffset else {
      return false
    }

    registration.applyOffset(next)
    return true
  }

  @discardableResult
  package func scrollTo(
    x: Int? = nil,
    y: Int? = nil,
    scopeIdentity: Identity?
  ) -> Bool {
    guard x != nil || y != nil else {
      return false
    }
    guard let route = firstRoute(matching: scopeIdentity),
      let registration = registrations[route.identity]
    else {
      return false
    }

    pendingExplicitScrollRoutes.insert(route.identity)
    supersedePendingCommands(on: route.identity, scopeIdentity: scopeIdentity)
    let currentOffset = registration.currentOffset()
    let next = clampedOffset(
      ScrollOffset(
        x: x ?? currentOffset.x,
        y: y ?? currentOffset.y
      ),
      in: route
    )
    guard next != currentOffset else {
      return false
    }

    registration.applyOffset(next)
    return true
  }

  @discardableResult
  package func sync(
    focusedIdentity: Identity?,
    focusRegions: [FocusRegion],
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget] = [],
    accessibilityNodes: [AccessibilityNode] = []
  ) -> Bool {
    defer {
      lastSyncedPositions = Dictionary(
        uniqueKeysWithValues: scrollRoutes.compactMap { route in
          registrations[route.identity].map { registration in
            (
              route.identity,
              SyncedPosition(
                offset: registration.currentOffset(), bindingSourceID: registration.bindingSourceID)
            )
          }
        })
    }
    updateGeometry(
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets
    )

    // Drop reveal anchors when focus leaves their target or their route departs. `sync` receives
    // the frame's full route set, so a route absent here has had its owning
    // ScrollView torn down (e.g. recreated under a new `.id`), leaving a dead
    // route identity cached. Unlike `reset()`/`removeSubtrees()` — which the run
    // loop drives every frame for republication and so must NOT touch this map —
    // `scrollRoutes` reflects genuine liveness. A still-present route retains
    // its anchor only while the same control remains focused.
    if !lastRevealAnchors.isEmpty {
      let liveRouteIdentities = Set(scrollRoutes.map(\.identity))
      lastRevealAnchors = lastRevealAnchors.filter {
        liveRouteIdentities.contains($0.key) && $0.value.focusedIdentity == focusedIdentity
      }
    }

    pendingExplicitScrollRoutes.formIntersection(scrollRoutes.map(\.identity))

    // Refine every pending command against the frame this sync received,
    // visiting routes in frame order, and only then report a change: all the
    // commands of one action land in the same eager rerender, before the next
    // commit's anchor preservation could supersede one of them (STUI-1243,
    // STUI-1264). Each refinement holds only while its route keeps the offset
    // or anchor the command wrote; any other input supersedes it.
    var refined = refineLazyTargets(in: scrollRoutes)
    if refineFarEdges(in: scrollRoutes) { refined = true }
    if refineCollectionTargets(in: scrollRoutes) { refined = true }
    // Last, so a retried target's own refinement waits for the frame that
    // lays out the offset it writes.
    if retryUnresolvedTargets() { refined = true }
    if refined { return true }

    let explicitScrollRoutes = pendingExplicitScrollRoutes
    pendingExplicitScrollRoutes.removeAll(keepingCapacity: true)

    guard let focusedIdentity,
      let focusedRegion = focusRegions.first(where: { $0.identity == focusedIdentity })
    else {
      return false
    }

    let focusedCursorAnchor =
      accessibilityNodes
      .first(where: { ($0.actionIdentity ?? $0.identity) == focusedIdentity })?
      .cursorAnchor
    let focusedCursorRect = focusedCursorAnchor.map {
      CellRect(
        origin: $0,
        size: CellSize(width: 1, height: 1)
      )
    }
    let revealRect = focusedCursorRect ?? focusedRegion.rect

    // Focus-reveal must be a one-shot response to a focus/cursor *change*, not a
    // standing constraint re-applied on every frame. Without this gate, once a
    // focused control is scrolled to the viewport edge, the next frame's reveal
    // scrolls it back into view, pinning user-initiated wheel/drag scrolling at
    // the focused control's position (the "scroll stalls partway, click a
    // surface to continue" bug).
    //
    // Ancestor routes reveal new focus, while deliberate
    // scroll input for unchanged focus takes precedence. Descendant routes inside
    // a focused editor also follow its text cursor. Geometry recovery runs before
    // focus regions are replaced and requires previous visibility. Carry corrected
    // rectangles through recorded scroll containment links so nested viewports
    // reveal in the same eager pass.

    var changed = false
    var containingScrollTargets: [Identity: CellRect] = [:]
    for route in scrollRoutes.reversed() {
      // An explicit `.id` re-roots identity, making the focused control an
      // identity SIBLING of its spatially enclosing scroll view — the
      // ancestry walk alone cannot pair them. The scroll-target table
      // records the true containment (targets are collected under their
      // enclosing scroll route), so a target pairing the focused identity
      // with this route makes it reveal-eligible too.
      let focusedTarget = latestScrollTargets.first { target in
        target.identity == focusedIdentity && target.scrollIdentity == route.identity
      }
      let containingTarget = latestScrollTargets.first { target in
        target.scrollIdentity == route.identity && containingScrollTargets[target.identity] != nil
      }
      let inheritedRect = containingTarget.flatMap { containingScrollTargets[$0.identity] }
      let followsCursor =
        focusedCursorRect != nil && route.identity.isDescendant(of: focusedIdentity)
      guard
        route.identity.isAncestor(of: focusedIdentity) || followsCursor
          || focusedTarget != nil || inheritedRect != nil,
        let registration = registrations[route.identity]
      else {
        continue
      }

      // Focus regions are viewport-clamped; reveal the unclamped target frame.
      let targetRect = focusedTarget?.rect ?? inheritedRect ?? revealRect
      let revealKey = ScrollRevealAnchor(
        focusedIdentity: focusedIdentity,
        cursorAnchor: followsCursor ? focusedCursorAnchor : nil
      )
      let previousReveal = lastRevealAnchors[route.identity]
      let isFreshReveal = previousReveal != revealKey
      lastRevealAnchors[route.identity] = revealKey
      let currentOffset = registration.currentOffset()
      let placedOffset = layoutOffset(
        currentOffset, in: route, preservesProducerOffset: registration.revealTarget != nil)
      containingScrollTargets[route.identity] = targetRect
      let hasNewInput =
        explicitScrollRoutes.contains(route.identity)
        || hasNewScrollInput(in: route, registration: registration)
      let preservesFocusedScroll = previousReveal?.focusedIdentity == focusedIdentity
      guard isFreshReveal, !(preservesFocusedScroll && hasNewInput) else {
        continue
      }

      let adjustedOffset = adjustedOffset(
        currentOffset,
        revealing: followsCursor ? revealRect : targetRect,
        in: route,
        preservesProducerOffset: registration.revealTarget != nil
      )
      guard adjustedOffset != currentOffset else {
        continue
      }

      registration.applyOffset(adjustedOffset)
      let correctedRect = CellRect(
        origin: CellPoint(
          x: targetRect.origin.x - (adjustedOffset.x - placedOffset.x),
          y: targetRect.origin.y - (adjustedOffset.y - placedOffset.y)),
        size: targetRect.size)
      containingScrollTargets[route.identity] = correctedRect
      changed = true
    }

    return changed
  }

  package func reset() {
    registrations.removeAll(keepingCapacity: true)
    latestScrollRoutes.removeAll(keepingCapacity: true)
    latestScrollTargets.removeAll(keepingCapacity: true)
    // `reset()` is the run loop's per-frame full registration republication, not
    // a teardown — the same scroll routes are re-registered immediately after.
    // `lastRevealAnchors` is focus-reveal interaction state that must SURVIVE
    // republication (otherwise focus-reveal re-fires every full-publication frame
    // and fights user scrolling again), so it is intentionally left untouched
    // here (and likewise in `removeSubtrees`, which the run loop also drives
    // every frame for scoped republication).
  }

  package func removeSubtrees(
    rootedAt roots: [Identity]
  ) {
    guard !roots.isEmpty else {
      return
    }

    for identity in registrations.keys.filter({
      identityMatchesAnySubtreeRoot($0, roots: roots)
    }) {
      registrations.removeValue(forKey: identity)
    }
    latestScrollRoutes.removeAll {
      identityMatchesAnySubtreeRoot($0.identity, roots: roots)
    }
    latestScrollTargets.removeAll {
      identityMatchesAnySubtreeRoot($0.identity, roots: roots)
        || identityMatchesAnySubtreeRoot($0.scrollIdentity, roots: roots)
    }
  }

  package func removeUnjustifiedRegistrations(_ record: (ViewNodeID) -> NodeHandlers?) {
    registrations = registrations.filter { identity, registration in
      guard let owner = registration.ownerViewNodeID else { return true }
      return record(owner)?.scrollPosition.registrations.contains { $0.identity == identity }
        == true
    }
  }

  package func restore(_ snapshot: [ScrollPositionRegistrationSnapshot]) {
    guard !snapshot.isEmpty else {
      return
    }

    for registration in snapshot {
      registrations[registration.identity] = registration
    }
  }

  package func snapshot() -> [ScrollPositionRegistrationSnapshot] {
    Array(registrations.values)
  }

  private func containingRoutes(
    startingAt identity: Identity, routes: [ScrollRoute], targets: [ScrollTarget]
  ) -> [ScrollRoute] {
    var chain: [ScrollRoute] = []
    var owner = identity
    for _ in routes {
      guard let route = routes.first(where: { $0.identity == owner }),
        !chain.contains(where: { $0.identity == owner })
      else { return [] }
      chain.append(route)
      guard let parent = targets.first(where: { $0.identity == owner }) else { return chain }
      owner = parent.scrollIdentity
    }
    return []
  }

  private func contentRect(
    _ rect: CellRect, in route: ScrollRoute, descendantOffset: ScrollOffset = .zero
  ) -> CellRect {
    CellRect(
      origin: CellPoint(
        x: rect.origin.x - route.contentBounds.origin.x + descendantOffset.x,
        y: rect.origin.y - route.contentBounds.origin.y + descendantOffset.y),
      size: rect.size)
  }

  private func layoutOffset(
    _ offset: ScrollOffset, in route: ScrollRoute, preservesProducerOffset: Bool
  ) -> ScrollOffset {
    if preservesProducerOffset { return offset }
    return clampedOffset(offset, in: route)
  }

  private func hasNewScrollInput(
    in route: ScrollRoute,
    registration: ScrollPositionRegistrationSnapshot
  ) -> Bool {
    if pendingExplicitScrollRoutes.contains(route.identity) { return true }
    guard let previous = lastSyncedPositions[route.identity] else { return false }
    guard previous.bindingSourceID == registration.bindingSourceID else { return true }
    let current = registration.currentOffset()
    if current == previous.offset { return false }
    // Only a correction actually applied at commit can explain a changed offset.
    if let correction = registration.committedOffsetCorrection,
      previous.offset == correction.requested, current == correction.corrected
    {
      return false
    }
    return true
  }

  private func adjustedOffset(
    _ currentOffset: ScrollOffset,
    revealing focusRect: CellRect,
    in route: ScrollRoute,
    preservesProducerOffset: Bool
  ) -> ScrollOffset {
    // A collection's target resolver owns its scroll range, including space
    // reserved for chrome and indicators. Ordinary ScrollView layout instead
    // clamps against the route bounds without writing back to its binding.
    // After a resize, apply reveal deltas to that clamped offset so a stale
    // binding cannot leave the requested target outside the viewport.
    var next = preservesProducerOffset ? currentOffset : clampedOffset(currentOffset, in: route)

    let exceedsViewportWidth = focusRect.size.width > route.viewportRect.size.width
    if focusRect.origin.x < route.viewportRect.origin.x || exceedsViewportWidth {
      next.x += focusRect.origin.x - route.viewportRect.origin.x
    } else if focusRect.maxX > route.viewportRect.maxX {
      next.x += focusRect.maxX - route.viewportRect.maxX
    }

    // A target taller than the viewport cannot show both edges. Keep its
    // start visible instead of moving past it to reveal the bottom.
    let exceedsViewportHeight = focusRect.size.height > route.viewportRect.size.height
    if focusRect.origin.y < route.viewportRect.origin.y || exceedsViewportHeight {
      next.y += focusRect.origin.y - route.viewportRect.origin.y
    } else if focusRect.maxY > route.viewportRect.maxY {
      next.y += focusRect.maxY - route.viewportRect.maxY
    }

    // Collections own their usable viewport, which can exclude fixed chrome
    // and overflow indicators. Preserve a visible axis's producer-owned offset
    // instead of normalizing it against the raw route bounds.
    if !preservesProducerOffset || next.x != currentOffset.x {
      next.x = clampedOffset(
        next.x,
        contentLength: route.contentBounds.size.width,
        viewportLength: route.viewportRect.size.width
      )
    }
    if !preservesProducerOffset || next.y != currentOffset.y {
      next.y = clampedOffset(
        next.y,
        contentLength: route.contentBounds.size.height,
        viewportLength: route.viewportRect.size.height
      )
    }
    let axes = registrations[route.identity]?.axes ?? [.horizontal, .vertical]
    if !axes.contains(.horizontal) { next.x = 0 }
    if !axes.contains(.vertical) { next.y = 0 }
    return next
  }

  private func adjustedOffset(
    _ currentOffset: ScrollOffset,
    scrolling targetRect: CellRect,
    anchor: UnitPoint?,
    in route: ScrollRoute,
    preservesProducerOffset: Bool
  ) -> ScrollOffset {
    // A non-finite anchor is ignored, as if no anchor were given.
    guard let anchor, anchor.x.isFinite, anchor.y.isFinite else {
      return adjustedOffset(
        currentOffset,
        revealing: targetRect,
        in: route,
        preservesProducerOffset: preservesProducerOffset
      )
    }

    var next = currentOffset
    next.x +=
      anchoredCoordinate(in: targetRect.origin.x, length: targetRect.size.width, anchor.x)
      - anchoredCoordinate(
        in: route.viewportRect.origin.x, length: route.viewportRect.size.width, anchor.x)
    next.y +=
      anchoredCoordinate(in: targetRect.origin.y, length: targetRect.size.height, anchor.y)
      - anchoredCoordinate(
        in: route.viewportRect.origin.y, length: route.viewportRect.size.height, anchor.y)

    return clampedOffset(next, in: route)
  }

  /// The live viewport rect published for the route matching `scopeIdentity`,
  /// or `nil` before the frame's geometry has synced (frame 1). Producers that
  /// size their own paging or interaction bands from the real viewport read it
  /// here rather than guessing a constant.
  package func viewportRect(
    scopeIdentity: Identity?
  ) -> CellRect? {
    firstRoute(matching: scopeIdentity)?.viewportRect
  }

  /// The largest anchor row the collection route matching `scopeIdentity`
  /// last published (see ``ScrollRoute/collectionMaximumAnchorRow``).
  package func collectionMaximumAnchorRow(
    scopeIdentity: Identity?
  ) -> Int? {
    firstRoute(matching: scopeIdentity)?.collectionMaximumAnchorRow
  }

  package func collectionScrollLayout(
    scopeIdentity: Identity?
  ) -> CollectionScrollLayout? {
    firstRoute(matching: scopeIdentity)?.collectionScrollLayout
  }

  /// Clamps `offset` against the live geometry of the route matching
  /// `scopeIdentity`. Returns `offset` unchanged when no route is known, so
  /// callers without published geometry keep their unclamped behavior.
  package func clampedOffset(
    _ offset: ScrollOffset,
    scopeIdentity: Identity?
  ) -> ScrollOffset {
    guard let route = firstRoute(matching: scopeIdentity) else {
      return offset
    }
    return clampedOffset(offset, in: route)
  }

  private func firstRoute(
    matching scopeIdentity: Identity?
  ) -> ScrollRoute? {
    if let direct = latestScrollRoutes.first(where: {
      routeMatchesScope($0.identity, scopeIdentity: scopeIdentity)
    }) {
      return direct
    }
    // An explicit `.id(_:)` re-roots a route's identity space out of the
    // reader's structural scope, so the identity-prefix check above can never
    // match it. Fall back to the walk-recorded structural host chain — and
    // only then, so co-scoped routes in the scope's own identity space keep
    // winning.
    return latestScrollRoutes.first {
      hostChainMatchesScope($0, scopeIdentity: scopeIdentity)
    }
  }

  private func firstTarget(
    matching query: ScrollTargetQuery,
    scopeIdentity: Identity?
  ) -> ScrollTarget? {
    if let direct = latestScrollTargets.first(where: {
      targetMatches($0, query: query)
        && routeMatchesScope($0.scrollIdentity, scopeIdentity: scopeIdentity)
    }) {
      return direct
    }
    // Same re-root fallback as `firstRoute(matching:)`, keyed through the
    // target's containing route.
    return latestScrollTargets.first { target in
      guard targetMatches(target, query: query),
        let route = latestScrollRoutes.first(where: { $0.identity == target.scrollIdentity })
      else {
        return false
      }
      return hostChainMatchesScope(route, scopeIdentity: scopeIdentity)
    }
  }

  private func routeMatchesScope(
    _ routeIdentity: Identity,
    scopeIdentity: Identity?
  ) -> Bool {
    guard let scopeIdentity else {
      return true
    }
    return routeIdentity == scopeIdentity || routeIdentity.isDescendant(of: scopeIdentity)
  }

  private func hostChainMatchesScope(
    _ route: ScrollRoute,
    scopeIdentity: Identity?
  ) -> Bool {
    guard let scopeIdentity else {
      return false
    }
    return route.structuralHostChain.contains {
      $0 == scopeIdentity || $0.isDescendant(of: scopeIdentity)
    }
  }

  private func targetMatches(
    _ target: ScrollTarget,
    query: ScrollTargetQuery
  ) -> Bool {
    if let identity = query.identity, target.identity == identity {
      return true
    }
    if let explicitIDComponent = query.explicitIDComponent,
      target.identity.lastComponent == explicitIDComponent
    {
      return true
    }
    return false
  }

  private func anchoredCoordinate(
    in origin: Int,
    length: Int,
    _ unit: Double
  ) -> Int {
    // A huge finite anchor saturates here; `clampedOffset` then bounds it.
    origin
      + SaturatingConversion.int(
        Double(max(0, length - 1)) * unit, rounding: .toNearestOrAwayFromZero)
  }

  private func clampedOffset(_ offset: ScrollOffset, in route: ScrollRoute) -> ScrollOffset {
    let axes = registrations[route.identity]?.axes ?? [.horizontal, .vertical]
    return ScrollOffset(
      x: axes.contains(.horizontal)
        ? clampedOffset(
          offset.x,
          contentLength: route.contentBounds.size.width,
          viewportLength: route.viewportRect.size.width) : 0,
      y: axes.contains(.vertical)
        ? clampedOffset(
          offset.y,
          contentLength: route.contentBounds.size.height,
          viewportLength: route.viewportRect.size.height) : 0)
  }

  private func clampedOffset(
    _ offset: Int,
    contentLength: Int,
    viewportLength: Int
  ) -> Int {
    min(max(0, offset), max(0, contentLength - viewportLength))
  }
}

/// Identifies what a scroll route last auto-revealed: the focused element and,
/// for a focused text input, its cursor anchor. `sync` re-reveals only when this
/// changes (focus moved or a cursor advanced), while deliberate
/// scrolling of an unchanged focused control retains priority. See `sync`.
private struct ScrollRevealAnchor: Equatable {
  var focusedIdentity: Identity
  var cursorAnchor: CellPoint?
}
