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
  package var currentOffset: @MainActor () -> ScrollOffset
  package var applyOffset: @MainActor (ScrollOffset) -> Void
  /// The authored binding's source token, when its producer supplies one.
  /// Registrations rebuild every resolve pass, so "registration replaced"
  /// never means "binding replaced" — this token is the only currency that
  /// distinguishes a re-resolve of the same authored binding (token stable)
  /// from a rebind to a different one (token changes). Consumed by scroll
  /// momentum to retire a fling whose binding was swapped out from under
  /// it. Nil (raw closures carry no identity) disables the distinction.
  package var bindingSourceID: AnyID?

  package init(
    identity: Identity,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void,
    bindingSourceID: AnyID? = nil
  ) {
    self.identity = identity
    self.currentOffset = currentOffset
    self.applyOffset = applyOffset
    self.bindingSourceID = bindingSourceID
  }
}

@MainActor
package final class LocalScrollPositionRegistry: Equatable {
  private var registrations: [Identity: ScrollPositionRegistrationSnapshot] = [:]
  private var latestScrollRoutes: [ScrollRoute] = []
  private var latestScrollTargets: [ScrollTarget] = []
  /// What each scroll route last auto-revealed (focused element + text cursor),
  /// keyed by the route identity. Lets `sync` fire focus-reveal only when focus
  /// (or a focused text cursor) *changes*, not as a standing per-frame constraint
  /// that would fight user-initiated wheel/drag scrolling.
  ///
  /// This is interaction session state, deliberately decoupled from the
  /// registration lifecycle: the run loop churns `reset()` (full republication)
  /// and `removeSubtrees()` (scoped republication) on essentially every frame to
  /// re-publish the offset closures, so this map must NOT be cleared by either —
  /// doing so re-fires focus-reveal every frame and reintroduces the stall. It
  /// is bounded by the number of distinct scroll-route identities the session
  /// ever shows and is released with the registry.
  private var lastRevealAnchors: [Identity: ScrollRevealAnchor] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalScrollPositionRegistry,
    rhs: LocalScrollPositionRegistry
  ) -> Bool {
    lhs === rhs
  }

  package func register(
    identity: Identity,
    currentOffset: @escaping @MainActor () -> ScrollOffset,
    applyOffset: @escaping @MainActor (ScrollOffset) -> Void,
    bindingSourceID: AnyID? = nil
  ) {
    let registration = ScrollPositionRegistrationSnapshot(
      identity: identity,
      currentOffset: currentOffset,
      applyOffset: applyOffset,
      bindingSourceID: bindingSourceID
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
      let offset = registration.currentOffset()
      var enriched = route
      enriched.contentOffset = CellPoint(x: offset.x, y: offset.y)
      return enriched
    }
  }

  @discardableResult
  package func scrollToTarget(
    _ query: ScrollTargetQuery,
    anchor: UnitPoint?,
    scopeIdentity: Identity?
  ) -> Bool {
    guard
      let target = latestScrollTargets.first(where: {
        targetMatches($0, query: query)
          && routeMatchesScope($0.scrollIdentity, scopeIdentity: scopeIdentity)
      }),
      let route = latestScrollRoutes.first(where: { $0.identity == target.scrollIdentity }),
      let registration = registrations[target.scrollIdentity]
    else {
      return false
    }

    let currentOffset = registration.currentOffset()
    let adjustedOffset = adjustedOffset(
      currentOffset,
      scrolling: target.rect,
      anchor: anchor,
      in: route
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

    let currentOffset = registration.currentOffset()
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

    next = clampedOffset(next, in: route)
    guard next != currentOffset else {
      return false
    }

    registration.applyOffset(next)
    return true
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

    let currentOffset = registration.currentOffset()
    let next = clampedOffset(
      ScrollOffset(x: currentOffset.x + deltaX, y: currentOffset.y + deltaY),
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
    updateGeometry(
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets
    )

    // Drop reveal anchors whose scroll route is no longer live. `sync` receives
    // the frame's full route set, so a route absent here has had its owning
    // ScrollView torn down (e.g. recreated under a new `.id`), leaving a dead
    // route identity cached. Unlike `reset()`/`removeSubtrees()` — which the run
    // loop drives every frame for republication and so must NOT touch this map —
    // `scrollRoutes` reflects genuine liveness, so a still-present route keeps
    // its anchor and a still-focused control does not re-fire focus-reveal.
    if !lastRevealAnchors.isEmpty {
      let liveRouteIdentities = Set(scrollRoutes.map(\.identity))
      lastRevealAnchors = lastRevealAnchors.filter { liveRouteIdentities.contains($0.key) }
    }

    guard let focusedIdentity,
      let focusedRegion = focusRegions.first(where: { $0.identity == focusedIdentity })
    else {
      return false
    }

    let focusedCursorAnchor =
      accessibilityNodes
      .first(where: { $0.identity == focusedIdentity })?
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
    // An ANCESTOR scroll view reveals a focused descendant only when focus
    // *moves* — matching SwiftUI, where typing or scrolling never re-asserts the
    // outer scroll. A DESCENDANT scroll (a text editor's own internal scroll,
    // INSIDE the focused input) instead follows the text cursor as it advances.
    // The gate key reflects exactly that: identity-only for ancestor routes,
    // identity + cursor for the descendant text-scroll. Note the control's rect
    // position is unusable as a signal — an off-screen focused control reports a
    // rect clamped to the viewport, and `cursorAnchor` for a non-text node is
    // just its (scrolling) position; both "change" as the user scrolls.

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
      let followsCursor =
        focusedCursorRect != nil && route.identity.isDescendant(of: focusedIdentity)
      guard
        route.identity.isAncestor(of: focusedIdentity) || followsCursor
          || focusedTarget != nil,
        let registration = registrations[route.identity]
      else {
        continue
      }

      // The focused REGION rect is viewport-clamped, so a relocation that
      // pushed the still-focused control offscreen both (a) leaves the
      // identity-only anchor unchanged and (b) reports a rect that already
      // reads as visible. The target rect is the unclamped placed frame:
      // key the anchor by its content-relative origin (scroll-invariant,
      // relocation-sensitive) and reveal against it.
      let contentAnchor = focusedTarget.map { target in
        CellPoint(
          x: target.rect.origin.x - route.contentBounds.origin.x,
          y: target.rect.origin.y - route.contentBounds.origin.y
        )
      }
      let revealKey = ScrollRevealAnchor(
        focusedIdentity: focusedIdentity,
        cursorAnchor: followsCursor ? focusedCursorAnchor : nil,
        contentAnchor: followsCursor ? nil : contentAnchor
      )
      let isFreshReveal = lastRevealAnchors[route.identity] != revealKey
      lastRevealAnchors[route.identity] = revealKey
      guard isFreshReveal else {
        continue
      }

      let currentOffset = registration.currentOffset()
      let adjustedOffset = adjustedOffset(
        currentOffset,
        revealing: followsCursor ? revealRect : (focusedTarget?.rect ?? revealRect),
        in: route
      )
      guard adjustedOffset != currentOffset else {
        continue
      }

      registration.applyOffset(adjustedOffset)
      return true
    }

    return false
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

  private func adjustedOffset(
    _ currentOffset: ScrollOffset,
    revealing focusRect: CellRect,
    in route: ScrollRoute
  ) -> ScrollOffset {
    var next = currentOffset

    if focusRect.origin.x < route.viewportRect.origin.x {
      next.x += focusRect.origin.x - route.viewportRect.origin.x
    } else if focusRect.maxX > route.viewportRect.maxX {
      next.x += focusRect.maxX - route.viewportRect.maxX
    }

    if focusRect.origin.y < route.viewportRect.origin.y {
      next.y += focusRect.origin.y - route.viewportRect.origin.y
    } else if focusRect.maxY > route.viewportRect.maxY {
      next.y += focusRect.maxY - route.viewportRect.maxY
    }

    next.x = clampedOffset(
      next.x,
      contentLength: route.contentBounds.size.width,
      viewportLength: route.viewportRect.size.width
    )
    next.y = clampedOffset(
      next.y,
      contentLength: route.contentBounds.size.height,
      viewportLength: route.viewportRect.size.height
    )
    return next
  }

  private func adjustedOffset(
    _ currentOffset: ScrollOffset,
    scrolling targetRect: CellRect,
    anchor: UnitPoint?,
    in route: ScrollRoute
  ) -> ScrollOffset {
    guard let anchor else {
      return adjustedOffset(
        currentOffset,
        revealing: targetRect,
        in: route
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
    latestScrollRoutes.first {
      routeMatchesScope($0.identity, scopeIdentity: scopeIdentity)
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
    origin + Int((Double(max(0, length - 1)) * unit).rounded())
  }

  private func clampedOffset(
    _ offset: ScrollOffset,
    in route: ScrollRoute
  ) -> ScrollOffset {
    ScrollOffset(
      x: clampedOffset(
        offset.x,
        contentLength: route.contentBounds.size.width,
        viewportLength: route.viewportRect.size.width
      ),
      y: clampedOffset(
        offset.y,
        contentLength: route.contentBounds.size.height,
        viewportLength: route.viewportRect.size.height
      )
    )
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
/// changes (focus moved, or a text cursor advanced) — never merely because the
/// user scrolled the still-focused control out of view. See `sync`.
private struct ScrollRevealAnchor: Equatable {
  var focusedIdentity: Identity
  var cursorAnchor: CellPoint?
  /// The focused target's content-relative origin (target rect against the
  /// route's content bounds). Invariant under user scrolling — placement
  /// shifts both uniformly — but changed by a structural relocation of the
  /// still-focused identity, which must re-reveal.
  var contentAnchor: CellPoint?
}
