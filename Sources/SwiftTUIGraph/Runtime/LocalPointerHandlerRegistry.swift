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
    case cancelled
    case moved
    case dragged(LocalPointerButton)
    case scrolled(deltaX: Int, deltaY: Int)
  }

  package var kind: Kind
  package var location: PointerLocation
  package var targetRect: CellRect
  package var scrollContext: LocalPointerScrollContext?
  package var namedCoordinateSpaces: [NamedCoordinateSpace: CellRect]
  package var timestamp: MonotonicInstant

  package init(
    kind: Kind,
    location: PointerLocation,
    targetRect: CellRect,
    scrollContext: LocalPointerScrollContext? = nil,
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect] = [:],
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
    namedCoordinateSpaces: [NamedCoordinateSpace: CellRect] = [:],
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

/// What a pointer dispatch did with an event, preserving the recognizer-role
/// information the RunLoop needs for control-activation decisions.
package enum PointerDispatchOutcome: Equatable, Sendable {
  /// An ordinary or high-priority lane recognized and claimed the interaction.
  case claimed
  /// Only simultaneous lanes recognized; control activation remains eligible.
  case observed
  /// A recognizer resolved to failed; nothing handled the event.
  case failed
  /// Nothing consumed the event.
  case ignored

  /// Whether routing should continue through the pointer interaction stream.
  package var wantsPointerStream: Bool {
    self == .claimed || self == .observed
  }
}

/// A recognizer aggregate that can preserve attachment roles through dispatch.
@MainActor
package protocol RoleAwarePointerDispatching: AnyObject {
  func handleClassified(event: LocalPointerEvent) -> PointerDispatchOutcome
  func handleDeadlineClassified(at instant: MonotonicInstant) -> PointerDispatchOutcome
}

@MainActor
package final class LocalPointerHandlerRegistry: Equatable {
  package typealias Handler = @MainActor (LocalPointerEvent) -> PointerDispatchOutcome
  package typealias HoverHandler = @MainActor @Sendable (HoverPhase) -> Void

  // Wheel modifiers contribute callbacks independently from the control's
  // primary handler. Ignoring a notch must leave the body handler available.
  private var wheelHandlers: [RouteID: [Handler]] = [:]
  private var wheelHandlerOwners: [RouteID: RuntimeRegistrationOwnerKey] = [:]
  private var wheelHandlerRecencies: [RouteID: UInt64] = [:]
  private var handlers: [RouteID: Handler] = [:]
  // Ordered stack per route: stacked `.onPointerHover` levels on one chain
  // node register under the exact same route key back-to-back within one
  // capture session, and every level must receive balanced phases.
  private var hoverHandlers: [RouteID: [HoverHandler]] = [:]
  private var handlerRecencies: [RouteID: UInt64] = [:]
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
    structuralKey: Identity? = nil,
    handler: @escaping Handler
  ) {
    if structuralKey != nil {
      let recency = ViewNodeContext.current?.runtimeRegistrationRecency ?? 0
      guard evictingCollidingGestureRoutes(for: routeID, recency: recency) else {
        return
      }
    }
    handlers[routeID] = handler
    handlerRecencies[routeID] = ViewNodeContext.current?.runtimeRegistrationRecency ?? 0
    handlerOwners[routeID] = .current(identity: routeID.identity)
    ViewNodeContext.current?.recordPointerHandlerRegistration(
      routeID: routeID,
      structuralKey: structuralKey,
      handler: handler
    )
  }

  /// Recency stamps for gesture-family routes (registrations that carried a
  /// `structuralKey`). A gesture route derives its identity from the entity
  /// below its authored site, so one authored gesture yields at most one
  /// meaningful handler per paired `(identity, kind)` — but a departed
  /// generation's detached entity home stays live and re-restores its stale
  /// record every frame, and subtree removal cannot reach a detached route
  /// by prefix. Freshest-recency pairing eviction (the hover registry's
  /// model) keeps exactly the live authored handler.
  private var gestureRouteRecencies: [RouteID: UInt64] = [:]

  /// Returns whether `routeID` should install: drops the incoming route when
  /// a strictly fresher paired route is live; otherwise evicts every staler
  /// or equal-recency paired route and stamps the incoming recency.
  private func evictingCollidingGestureRoutes(
    for routeID: RouteID,
    recency: UInt64
  ) -> Bool {
    for existing in handlers.keys
    where existing != routeID && existing.pairsIgnoringOwner(with: routeID) {
      if (gestureRouteRecencies[existing] ?? 0) > recency {
        return false
      }
      handlers.removeValue(forKey: existing)
      handlerOwners.removeValue(forKey: existing)
      handlerRecencies.removeValue(forKey: existing)
      gestureRouteRecencies.removeValue(forKey: existing)
    }
    gestureRouteRecencies[routeID] = max(recency, gestureRouteRecencies[routeID] ?? 0)
    return true
  }

  package func registerHover(
    routeID: RouteID,
    structuralKey: Identity? = nil,
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
    // Owner under the authored (structural) identity when supplied: a derived
    // entity route's own identity lives in a re-rooted space that
    // subtree-removal prefixes never reach.
    hoverHandlerOwners[routeID] = .current(identity: structuralKey ?? routeID.identity)
    hoverHandlerRecencies[routeID] = recency
    ViewNodeContext.current?.recordPointerHoverHandlerRegistration(
      routeID: routeID,
      structuralKey: structuralKey,
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

  package func registerWheel(
    routeID: RouteID,
    structuralKey: Identity? = nil,
    handler: @escaping Handler
  ) {
    let recency = ViewNodeContext.current?.runtimeRegistrationRecency ?? 0
    guard evictingCollidingWheelRoutes(for: routeID, recency: recency) else {
      return
    }
    // A strictly fresher stamp starts this pass's stack for the route; an
    // equal stamp appends — stacked `.onScrollWheel` levels on one chain
    // register back-to-back within one capture session. Dispatch runs outer
    // callbacks first; a staler stamp is a shadowed re-feed and is dropped.
    if let existingRecency = wheelHandlerRecencies[routeID] {
      if recency > existingRecency {
        wheelHandlers[routeID] = [handler]
      } else if recency == existingRecency {
        wheelHandlers[routeID, default: []].append(handler)
      } else {
        return
      }
    } else {
      wheelHandlers[routeID] = [handler]
    }
    // Owner under the authored (structural) identity when supplied: a derived
    // entity route's own identity lives in a re-rooted space that
    // subtree-removal prefixes never reach.
    wheelHandlerOwners[routeID] = .current(identity: structuralKey ?? routeID.identity)
    wheelHandlerRecencies[routeID] = recency
    ViewNodeContext.current?.recordPointerWheelHandlerRegistration(
      routeID: routeID,
      structuralKey: structuralKey,
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
  private func evictingCollidingWheelRoutes(
    for routeID: RouteID,
    recency: UInt64
  ) -> Bool {
    let collidingRoutes = wheelHandlers.keys.filter { existing in
      existing.pairsIgnoringOwner(with: routeID) && existing != routeID
    }
    for existing in collidingRoutes {
      let existingRecency = wheelHandlerRecencies[existing] ?? 0
      if existingRecency < recency {
        wheelHandlers.removeValue(forKey: existing)
        wheelHandlerOwners.removeValue(forKey: existing)
        wheelHandlerRecencies.removeValue(forKey: existing)
      } else if existingRecency > recency {
        return false
      }
    }
    return true
  }

  package func hasHandler(
    routeID: RouteID
  ) -> Bool {
    handlers[routeID] != nil || wheelHandlers[routeID] != nil
  }

  package func hasHandler(
    pairingWith routeID: RouteID
  ) -> Bool {
    handlerRouteID(pairingWith: routeID) != nil || wheelRouteID(pairingWith: routeID) != nil
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

  /// Resolves an exact key first, then the freshest paired registration.
  /// Node allocation order only breaks ties: an older node can re-register
  /// after a newer, abandoned node when modifier chains collapse.
  package func handlerRouteID(
    pairingWith routeID: RouteID
  ) -> RouteID? {
    if handlers[routeID] != nil {
      return routeID
    }
    return handlers.keys
      .filter { $0.pairsIgnoringOwner(with: routeID) }
      .max { lhs, rhs in
        let lhsRecency = handlerRecencies[lhs] ?? 0
        let rhsRecency = handlerRecencies[rhs] ?? 0
        if lhsRecency != rhsRecency { return lhsRecency < rhsRecency }
        return Self.staleOwnerFirst(lhs.ownerNodeID, rhs.ownerNodeID)
      }
      ?? wheelRouteID(pairingWith: routeID)
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

  package func wheelRouteID(
    pairingWith routeID: RouteID
  ) -> RouteID? {
    if wheelHandlers[routeID] != nil {
      return routeID
    }
    return wheelHandlers.keys
      .filter { $0.pairsIgnoringOwner(with: routeID) }
      .max { lhs, rhs in
        let lhsRecency = wheelHandlerRecencies[lhs] ?? 0
        let rhsRecency = wheelHandlerRecencies[rhs] ?? 0
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
  ) -> PointerDispatchOutcome {
    if case .scrolled = event.kind, let wheelRoute = wheelRouteID(pairingWith: routeID) {
      // Inner bodies resolve first; outer authored handlers get first refusal.
      for handler in (wheelHandlers[wheelRoute] ?? []).reversed() {
        let result = handler(event)
        if result != .ignored && result != .failed { return result }
      }
    }
    guard let resolved = handlerRouteID(pairingWith: routeID) else { return .ignored }
    return handlers[resolved]?(event) ?? .ignored
  }

  package func dispatchHover(
    routeID: RouteID,
    phase: HoverPhase
  ) {
    // The caller's route may carry a stale `ownerNodeID` (a hover exit paired
    // against a route captured before the hovered node re-minted), so resolve
    // through the same explicit pairing query the pointer release path uses.
    // Every stacked level receives the phase, in registration order.
    for handler in hoverCallbacks(pairingWith: routeID) {
      handler(phase)
    }
  }

  /// A bounded snapshot of one route's stacked callbacks. The run loop keeps
  /// the current hover's callbacks until its matching exit, including when
  /// publication removes the route from this registry first.
  package func hoverCallbacks(pairingWith routeID: RouteID) -> [HoverHandler] {
    guard let resolved = hoverRouteID(pairingWith: routeID) else { return [] }
    return hoverHandlers[resolved] ?? []
  }

  package func reset() {
    handlers.removeAll(keepingCapacity: true)
    wheelHandlers.removeAll(keepingCapacity: true)
    wheelHandlerOwners.removeAll(keepingCapacity: true)
    wheelHandlerRecencies.removeAll(keepingCapacity: true)
    hoverHandlers.removeAll(keepingCapacity: true)
    handlerOwners.removeAll(keepingCapacity: true)
    handlerRecencies.removeAll(keepingCapacity: true)
    hoverHandlerOwners.removeAll(keepingCapacity: true)
    hoverHandlerRecencies.removeAll(keepingCapacity: true)
    gestureRouteRecencies.removeAll(keepingCapacity: true)
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
      handlerRecencies.removeValue(forKey: routeID)
    }
    wheelHandlers.removeAll(keepingCapacity: true)
    wheelHandlerOwners.removeAll(keepingCapacity: true)
    wheelHandlerRecencies.removeAll(keepingCapacity: true)
    hoverHandlers.removeAll(keepingCapacity: true)
    hoverHandlerOwners.removeAll(keepingCapacity: true)
    hoverHandlerRecencies.removeAll(keepingCapacity: true)
    gestureRouteRecencies = gestureRouteRecencies.filter { routeID, _ in
      preservedIdentities.contains(routeID.identity)
    }
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
      handlerRecencies.removeValue(forKey: routeID)
      gestureRouteRecencies.removeValue(forKey: routeID)
    }
    for routeID in hoverHandlers.keys.filter({
      (hoverHandlerOwners[$0] ?? .init(identity: $0.identity)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0.identity)
    }) {
      hoverHandlers.removeValue(forKey: routeID)
      hoverHandlerOwners.removeValue(forKey: routeID)
      hoverHandlerRecencies.removeValue(forKey: routeID)
    }
    for routeID in wheelHandlers.keys.filter({
      (wheelHandlerOwners[$0] ?? .init(identity: $0.identity)).matchesAnySubtreeRoot(roots)
        && !preservedIdentities.contains($0.identity)
    }) {
      wheelHandlers.removeValue(forKey: routeID)
      wheelHandlerOwners.removeValue(forKey: routeID)
      wheelHandlerRecencies.removeValue(forKey: routeID)
    }
  }

  /// Releases pointer callbacks spared during an active interaction once
  /// both the recognizer and the owning node have departed. Wheel and hover
  /// callbacks have independent storage and participate in the same sweep.
  /// Primary handlers require a gesture-family stamp; plain control handlers
  /// keep their separate structural lifetime. Live owners, paired identities,
  /// and owners without a node ID remain. Adoption rehomes owner keys to the
  /// adopting node, so its callbacks remain live even with an older route ID.
  package func removeUnpairedGestureFamilyRoutes(
    pairedIdentities: Set<Identity>,
    keeping liveNodeIDs: Set<ViewNodeID>
  ) {
    func ownerHasDeparted(_ routeID: RouteID, owner: RuntimeRegistrationOwnerKey?) -> Bool {
      guard !pairedIdentities.contains(routeID.identity),
        let ownerNodeID = owner?.viewNodeID
      else {
        return false
      }
      return !liveNodeIDs.contains(ownerNodeID)
    }
    for routeID in handlers.keys.filter({
      gestureRouteRecencies[$0] != nil && ownerHasDeparted($0, owner: handlerOwners[$0])
    }) {
      handlers.removeValue(forKey: routeID)
      handlerOwners.removeValue(forKey: routeID)
      handlerRecencies.removeValue(forKey: routeID)
      gestureRouteRecencies.removeValue(forKey: routeID)
    }
    for routeID in wheelHandlers.keys.filter({
      ownerHasDeparted($0, owner: wheelHandlerOwners[$0])
    }) {
      wheelHandlers.removeValue(forKey: routeID)
      wheelHandlerOwners.removeValue(forKey: routeID)
      wheelHandlerRecencies.removeValue(forKey: routeID)
    }
    for routeID in hoverHandlers.keys.filter({
      ownerHasDeparted($0, owner: hoverHandlerOwners[$0])
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

  package func snapshotWheel() -> [RouteID: [Handler]] {
    wheelHandlers
  }

  package func restore(
    _ snapshot: [RouteID: Handler],
    ownersByRouteID: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    structuralRoutes: [Identity: RouteID] = [:],
    recency: UInt64 = 0
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    // Gesture-family routes (the record's replacement-map values) restore
    // through recency-gated pairing eviction: a stale detached node's
    // re-restore must not resurrect a superseded generation's route over the
    // live one, and a fresh restore evicts the stale generations it
    // supersedes.
    let gestureRoutes = Set(structuralRoutes.values)
    for (routeID, handler) in snapshot {
      if gestureRoutes.contains(routeID) {
        guard evictingCollidingGestureRoutes(for: routeID, recency: recency) else {
          continue
        }
      }
      if let existingRecency = handlerRecencies[routeID], recency < existingRecency {
        continue
      }
      handlers[routeID] = handler
      handlerRecencies[routeID] = recency
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
  package func restoreWheel(
    _ snapshot: [RouteID: [Handler]],
    ownersByRouteID: [RouteID: RuntimeRegistrationOwnerKey] = [:],
    recency: UInt64 = 0
  ) {
    guard !snapshot.isEmpty else {
      return
    }

    for (routeID, stackedHandlers) in snapshot {
      guard !stackedHandlers.isEmpty,
        evictingCollidingWheelRoutes(for: routeID, recency: recency)
      else {
        continue
      }
      // Whole-stack replace at an equal-or-fresher stamp: the committed
      // record carries the route's complete stack, and replacing (never
      // appending) keeps the per-frame double restore idempotent. An older
      // snapshot must not clobber a live re-registration.
      if let existingRecency = wheelHandlerRecencies[routeID],
        recency < existingRecency
      {
        continue
      }
      wheelHandlers[routeID] = stackedHandlers
      wheelHandlerOwners[routeID] =
        ownersByRouteID[routeID] ?? .init(identity: routeID.identity)
      wheelHandlerRecencies[routeID] = recency
    }
  }
}
