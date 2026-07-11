package enum LocalPointerButton: Equatable, Sendable {
  case primary
  case middle
  case secondary
}

package struct LocalPointerScrollContext: Equatable, Sendable {
  package var viewportRect: CellRect
  package var contentBounds: CellRect

  package init(
    viewportRect: CellRect,
    contentBounds: CellRect
  ) {
    self.viewportRect = viewportRect
    self.contentBounds = contentBounds
  }
}

package struct LocalPointerEvent: Equatable, Sendable {
  package enum Kind: Equatable, Sendable {
    case down(LocalPointerButton)
    case up(LocalPointerButton)
    case moved
    case dragged(LocalPointerButton)
    case scrolled(deltaX: Int, deltaY: Int)
  }

  package var kind: Kind
  package var location: PointerLocation
  package var targetRect: CellRect
  package var scrollContext: LocalPointerScrollContext?
  package var namedCoordinateSpaces: [String: CellRect]
  package var timestamp: MonotonicInstant

  package init(
    kind: Kind,
    location: PointerLocation,
    targetRect: CellRect,
    scrollContext: LocalPointerScrollContext? = nil,
    namedCoordinateSpaces: [String: CellRect] = [:],
    timestamp: MonotonicInstant = .now()
  ) {
    self.kind = kind
    self.location = location
    self.targetRect = targetRect
    self.scrollContext = scrollContext
    self.namedCoordinateSpaces = namedCoordinateSpaces
    self.timestamp = timestamp
  }

  /// Builds a cell-only fallback event for the cell containing `location`.
  ///
  /// Callers with fractional input should pass a ``PointerLocation`` directly.
  package init(
    kind: Kind,
    location: Point,
    targetRect: CellRect,
    scrollContext: LocalPointerScrollContext? = nil,
    namedCoordinateSpaces: [String: CellRect] = [:],
    timestamp: MonotonicInstant = .now()
  ) {
    self.init(
      kind: kind,
      location: .cellFallback(location.containingCell),
      targetRect: targetRect,
      scrollContext: scrollContext,
      namedCoordinateSpaces: namedCoordinateSpaces,
      timestamp: timestamp
    )
  }
}

@MainActor
package final class LocalPointerHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (LocalPointerEvent) -> Bool
  package typealias HoverHandler = @MainActor @Sendable (HoverPhase) -> Void

  private var handlers: [RouteID: Handler] = [:]
  // Ordered stack per route: stacked `.onPointerHover` levels on one chain
  // node register under the exact same route key back-to-back within one
  // capture session, and every level must receive balanced phases.
  private var hoverHandlers: [RouteID: [HoverHandler]] = [:]
  private var handlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  private var hoverHandlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  // Recency (the contributing node's visited-frame stamp) per hover route.
  // A hover registration can be re-captured on a DIFFERENT node when the
  // slot's evaluation topology changes between frames (stacked modifier levels
  // collapse onto one node on re-resolve); the abandoned node keeps a live,
  // never-re-captured copy under the same identity with a different
  // `ownerNodeID`. On insert, a fresher registration for the same
  // owner-agnostic route evicts the stale one so the registry holds one entry
  // per logical hover stack.
  private var hoverHandlerRecencies: [RouteID: UInt64] = [:]

  package init() {}

  nonisolated package static func == (
    lhs: LocalPointerHandlerRegistry, rhs: LocalPointerHandlerRegistry
  )
    -> Bool
  {
    lhs === rhs
  }

  package func register(
    routeID: RouteID,
    handler: @escaping Handler
  ) {
    handlers[routeID] = handler
    handlerOwners[routeID] = .current(identity: routeID.identity)
    ViewNodeContext.current?.recordPointerHandlerRegistration(
      routeID: routeID,
      handler: handler
    )
  }

  package func registerHover(
    routeID: RouteID,
    handler: @escaping HoverHandler
  ) {
    let recency = ViewNodeContext.current?.runtimeRegistrationRecency ?? 0
    guard evictingCollidingHoverRoutes(for: routeID, recency: recency) else {
      return
    }
    // A strictly fresher stamp starts this pass's stack for the route; an
    // equal stamp appends — stacked `.onPointerHover` levels on one chain
    // register back-to-back within one capture session and every level must
    // dispatch; a staler stamp is a shadowed re-feed and is dropped.
    if let existingRecency = hoverHandlerRecencies[routeID] {
      if recency > existingRecency {
        hoverHandlers[routeID] = [handler]
      } else if recency == existingRecency {
        hoverHandlers[routeID, default: []].append(handler)
      } else {
        return
      }
    } else {
      hoverHandlers[routeID] = [handler]
    }
    hoverHandlerOwners[routeID] = .current(identity: routeID.identity)
    hoverHandlerRecencies[routeID] = recency
    ViewNodeContext.current?.recordPointerHoverHandlerRegistration(
      routeID: routeID,
      handler: handler
    )
  }

  /// Cross-owner collision policy, unchanged from the single-handler model:
  /// an entry for the same identity+kind under a different owner whose
  /// contributing node has a strictly older visited stamp is an abandoned
  /// level's shadowed copy — evict it. A strictly fresher existing entry wins
  /// instead (the incoming one is the shadowed copy being re-restored) —
  /// returns `false` so the caller drops the incoming registration. Equal
  /// recency keeps both owners' entries distinct.
  private func evictingCollidingHoverRoutes(
    for routeID: RouteID,
    recency: UInt64
  ) -> Bool {
    let collidingRoutes = hoverHandlers.keys.filter { existing in
      existing.pairsIgnoringOwner(with: routeID) && existing != routeID
    }
    for existing in collidingRoutes {
      let existingRecency = hoverHandlerRecencies[existing] ?? 0
      if existingRecency < recency {
        hoverHandlers.removeValue(forKey: existing)
        hoverHandlerOwners.removeValue(forKey: existing)
        hoverHandlerRecencies.removeValue(forKey: existing)
      } else if existingRecency > recency {
        return false
      }
    }
    return true
  }

  package func hasHandler(
    routeID: RouteID
  ) -> Bool {
    handlers[routeID] != nil
  }

  package func hasHandler(
    pairingWith routeID: RouteID
  ) -> Bool {
    handlerRouteID(pairingWith: routeID) != nil
  }

  package func hasHoverHandler(
    routeID: RouteID
  ) -> Bool {
    hoverHandlers[routeID] != nil
  }

  package func hasHoverHandler(
    pairingWith routeID: RouteID
  ) -> Bool {
    hoverRouteID(pairingWith: routeID) != nil
  }

  package var hasHoverSubscribers: Bool {
    !hoverHandlers.isEmpty
  }

  /// Resolves the registered key that pairs with `routeID`: the exact key when
  /// present, else — after a re-mint changed the route's `ownerNodeID` — the
  /// paired key (same identity + kind) whose owner is freshest. Among several
  /// paired entries (a stale shadowed copy next to a live re-registration) the
  /// highest `ownerNodeID` wins, `nil`-owner entries last: node IDs allocate
  /// monotonically, so the freshest registration is the live one. The pick is
  /// a total order, so delivery is deterministic where the old wildcard
  /// `RouteID.==` dictionary probe was hash-seeded.
  package func handlerRouteID(
    pairingWith routeID: RouteID
  ) -> RouteID? {
    if handlers[routeID] != nil {
      return routeID
    }
    return handlers.keys
      .filter { $0.pairsIgnoringOwner(with: routeID) }
      .max { Self.staleOwnerFirst($0.ownerNodeID, $1.ownerNodeID) }
  }

  /// Hover counterpart of ``handlerRouteID(pairingWith:)``. Prefers the entry
  /// with the freshest recency stamp (the contributing node's visited frame),
  /// tie-broken by owner, so a stale shadowed copy that survived eviction can
  /// never outrank the live re-registration.
  package func hoverRouteID(
    pairingWith routeID: RouteID
  ) -> RouteID? {
    if hoverHandlers[routeID] != nil {
      return routeID
    }
    return hoverHandlers.keys
      .filter { $0.pairsIgnoringOwner(with: routeID) }
      .max { lhs, rhs in
        let lhsRecency = hoverHandlerRecencies[lhs] ?? 0
        let rhsRecency = hoverHandlerRecencies[rhs] ?? 0
        if lhsRecency != rhsRecency {
          return lhsRecency < rhsRecency
        }
        return Self.staleOwnerFirst(lhs.ownerNodeID, rhs.ownerNodeID)
      }
  }

  private static func staleOwnerFirst(
    _ lhs: ViewNodeID?,
    _ rhs: ViewNodeID?
  ) -> Bool {
    switch (lhs, rhs) {
    case (.none, .some):
      true
    case (.some, .none), (.none, .none):
      false
    case (.some(let lhsID), .some(let rhsID)):
      lhsID < rhsID
    }
  }

  @discardableResult
  package func dispatch(
    routeID: RouteID,
    event: LocalPointerEvent
  ) -> Bool {
    guard let resolved = handlerRouteID(pairingWith: routeID) else {
      return false
    }
    return handlers[resolved]?(event) ?? false
  }

  package func dispatchHover(
    routeID: RouteID,
    phase: HoverPhase
  ) {
    // The caller's route may carry a stale `ownerNodeID` (a hover exit paired
    // against a route captured before the hovered node re-minted), so resolve
    // through the same explicit pairing query the pointer release path uses.
    guard let resolved = hoverRouteID(pairingWith: routeID) else {
      return
    }
    // Every stacked level receives the phase, in registration order.
    for handler in hoverHandlers[resolved] ?? [] {
      handler(phase)
    }
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
    hoverHandlers.removeAll(keepingCapacity: true)
    handlerOwners.removeAll(keepingCapacity: true)
    hoverHandlerOwners.removeAll(keepingCapacity: true)
    hoverHandlerRecencies.removeAll(keepingCapacity: true)
  }

  package func reset(
    preservingRouteHandlersFor preservedIdentities: Set<Identity>
  ) {
    guard !preservedIdentities.isEmpty else {
      reset()
      return
    }

    for routeID in handlers.keys.filter({ !preservedIdentities.contains($0.identity) }) {
      handlers.removeValue(forKey: routeID)
      handlerOwners.removeValue(forKey: routeID)
    }
    hoverHandlers.removeAll(keepingCapacity: true)
    hoverHandlerOwners.removeAll(keepingCapacity: true)
    hoverHandlerRecencies.removeAll(keepingCapacity: true)
  }

  package func removeSubtrees(
    rootedAt roots: [Identity],
    preserving preservedIdentities: Set<Identity> = []
  ) {
    guard !roots.isEmpty else {
      return
    }

    for routeID in handlers.keys.filter({
      (handlerOwners[$0] ?? .init(identity: $0.identity)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0.identity)
    }) {
      handlers.removeValue(forKey: routeID)
      handlerOwners.removeValue(forKey: routeID)
    }
    for routeID in hoverHandlers.keys.filter({
      (hoverHandlerOwners[$0] ?? .init(identity: $0.identity)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0.identity)
    }) {
      hoverHandlers.removeValue(forKey: routeID)
      hoverHandlerOwners.removeValue(forKey: routeID)
      hoverHandlerRecencies.removeValue(forKey: routeID)
    }
  }

  package func snapshot() -> [RouteID: Handler] {
    handlers
  }

  package func snapshotHover() -> [RouteID: [HoverHandler]] {
    hoverHandlers
  }

  package func restore(
    _ snapshot: [RouteID: Handler],
    ownersByRouteID: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (routeID, handler) in snapshot {
      handlers[routeID] = handler
      handlerOwners[routeID] = ownersByRouteID[routeID] ?? .init(identity: routeID.identity)
    }
  }

  package func restoreHover(
    _ snapshot: [RouteID: [HoverHandler]],
    ownersByRouteID: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    recency: UInt64 = 0
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (routeID, stackedHandlers) in snapshot {
      guard !stackedHandlers.isEmpty,
        evictingCollidingHoverRoutes(for: routeID, recency: recency)
      else {
        continue
      }
      // Whole-stack replace at an equal-or-fresher stamp: the committed
      // record carries the route's complete stack, and replacing (never
      // appending) keeps the per-frame double restore idempotent. An older
      // snapshot must not clobber a live re-registration.
      if let existingRecency = hoverHandlerRecencies[routeID],
        recency < existingRecency
      {
        continue
      }
      hoverHandlers[routeID] = stackedHandlers
      hoverHandlerOwners[routeID] =
        ownersByRouteID[routeID] ?? .init(identity: routeID.identity)
      hoverHandlerRecencies[routeID] = recency
    }
  }
}
