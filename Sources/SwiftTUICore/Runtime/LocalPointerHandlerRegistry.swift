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
  private var hoverHandlers: [RouteID: HoverHandler] = [:]
  private var handlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  private var hoverHandlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  // Recency (the contributing node's visited-frame stamp) per hover route.
  // A hover registration can be re-captured on a DIFFERENT node when the
  // slot's evaluation topology changes between frames (stacked modifier levels
  // collapse onto one node on re-resolve); the abandoned node keeps a live,
  // never-re-captured copy under the same identity with a different
  // `ownerNodeID`. On insert, a fresher registration for the same
  // owner-agnostic route evicts the stale one so the registry holds one entry
  // per logical hover handler.
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
    insertHoverHandler(
      routeID: routeID,
      handler: handler,
      owner: .current(identity: routeID.identity),
      recency: ViewNodeContext.current?.runtimeRegistrationRecency ?? 0
    )
    ViewNodeContext.current?.recordPointerHoverHandlerRegistration(
      routeID: routeID,
      handler: handler
    )
  }

  /// Inserts a hover handler, evicting any stale same-owner-agnostic entry: an
  /// entry for the same identity+kind whose contributing node has a strictly
  /// older visited stamp is an abandoned level's shadowed copy, not a distinct
  /// stacked handler. A strictly fresher existing entry wins instead (the
  /// incoming one is the shadowed copy being re-restored). Equal recency keeps
  /// both — genuinely stacked same-frame registrations stay distinct per owner.
  private func insertHoverHandler(
    routeID: RouteID,
    handler: @escaping HoverHandler,
    owner: RuntimeRegistrationOwnerKey,
    recency: UInt64
  ) {
    let collidingRoutes = hoverHandlers.keys.filter { existing in
      existing == routeID.ownerAgnostic && existing != routeID
    }
    for existing in collidingRoutes {
      let existingRecency = hoverHandlerRecencies[existing] ?? 0
      if existingRecency < recency {
        hoverHandlers.removeValue(forKey: existing)
        hoverHandlerOwners.removeValue(forKey: existing)
        hoverHandlerRecencies.removeValue(forKey: existing)
      } else if existingRecency > recency {
        return
      }
    }
    hoverHandlers[routeID] = handler
    hoverHandlerOwners[routeID] = owner
    hoverHandlerRecencies[routeID] = recency
  }

  package func hasHandler(
    routeID: RouteID
  ) -> Bool {
    handlers[routeID] != nil
  }

  package func hasHoverHandler(
    routeID: RouteID
  ) -> Bool {
    hoverHandlers[routeID] != nil
  }

  package var hasHoverSubscribers: Bool {
    !hoverHandlers.isEmpty
  }

  @discardableResult
  package func dispatch(
    routeID: RouteID,
    event: LocalPointerEvent
  ) -> Bool {
    handlers[routeID]?(event) ?? false
  }

  package func dispatchHover(
    routeID: RouteID,
    phase: HoverPhase
  ) {
    if let handler = hoverHandlers[routeID] {
      handler(phase)
      return
    }
    // The caller's route may carry a stale `ownerNodeID` (a hover exit paired
    // against a route captured before the hovered node re-minted). The stale
    // registry entry that used to satisfy that exact match is evicted on
    // re-registration now, so fall back to the same owner-agnostic pairing the
    // pointer release path uses.
    hoverHandlers.first { existing, _ in
      existing == routeID.ownerAgnostic
    }?.value(phase)
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

  package func snapshotHover() -> [RouteID: HoverHandler] {
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
    _ snapshot: [RouteID: HoverHandler],
    ownersByRouteID: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    recency: UInt64 = 0
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (routeID, handler) in snapshot {
      insertHoverHandler(
        routeID: routeID,
        handler: handler,
        owner: ownersByRouteID[routeID] ?? .init(identity: routeID.identity),
        recency: recency
      )
    }
  }
}
