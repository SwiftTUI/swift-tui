import SwiftTUICore

extension RunLoop {
  package struct HitTarget {
    var region: InteractionRegion
    var focusIdentity: Identity?
  }

  /// Returns whether a click at `location` should move focus to `focusIdentity`.
  /// Focus is set unless a more-specific descendant focus region contains the
  /// point and is smaller than the candidate (indicating a child control, not
  /// an overlay like a scroll indicator).
  package func shouldClickFocus(
    _ focusIdentity: Identity,
    at location: PointerLocation
  ) -> Bool {
    if isActivationIdentity(focusIdentity) {
      return true
    }

    let candidateRegion = latestSemanticSnapshot.focusRegions.first {
      $0.identity == focusIdentity
    }
    guard let candidateRect = candidateRegion?.rect else {
      return true
    }

    let candidateArea = candidateRect.size.width * candidateRect.size.height
    let hasSmallerDescendant = latestSemanticSnapshot.focusRegions.contains { region in
      guard region.identity != focusIdentity,
        region.rect.contains(location.cell),
        region.identity.isDescendant(of: focusIdentity)
      else {
        return false
      }
      let regionArea = region.rect.size.width * region.rect.size.height
      return regionArea < candidateArea
    }
    return !hasSmallerDescendant
  }

  package func scrollTarget(
    at location: PointerLocation,
    deltaX: Int = 0,
    deltaY: Int = 0
  ) -> ScrollRoute? {
    let routes = latestSemanticSnapshot.scrollRoutes
      .filter { route in
        guard route.viewportRect.contains(location.cell) else {
          return false
        }
        let scrollsHorizontally = route.contentBounds.size.width > route.viewportRect.size.width
        let scrollsVertically = route.contentBounds.size.height > route.viewportRect.size.height
        if deltaX != 0, !scrollsHorizontally { return false }
        if deltaY != 0, !scrollsVertically { return false }
        return scrollsHorizontally || scrollsVertically
      }

    let scrollViewIdentities = Set(
      latestSemanticSnapshot.selectionRoutes.lazy
        .filter { $0.role == .scrollView }
        .map(\.identity)
    )
    return routes.last { scrollViewIdentities.contains($0.identity) }
      ?? routes.last
  }

  package func hitTarget(
    at location: PointerLocation
  ) -> HitTarget? {
    guard
      let region = latestSemanticSnapshot.interactionRegions
        .filter({ $0.contains(location) })
        .max(by: { $0.hitTestOrder < $1.hitTestOrder })
    else {
      return nil
    }

    return HitTarget(
      region: region,
      focusIdentity: focusIdentity(for: region.identity)
    )
  }

  package func interactionRegion(
    routeID: RouteID
  ) -> InteractionRegion? {
    latestSemanticSnapshot.interactionRegions.first { region in
      region.routeID == routeID
    }
  }

  package func focusIdentity(
    for identity: Identity
  ) -> Identity? {
    var current: Identity? = identity
    while let candidate = current {
      if latestSemanticSnapshot.focusRegions.contains(where: { $0.identity == candidate }) {
        return candidate
      }
      self.assertNoInfiniteIdentityLoop(candidate)
      current = candidate.parent
    }
    return nil
  }

  package func scrollContext(
    for identity: Identity
  ) -> LocalPointerScrollContext? {
    var current: Identity? = identity
    while let candidate = current {
      if let route = latestSemanticSnapshot.scrollRoutes.first(where: { $0.identity == candidate })
      {
        return .init(
          viewportRect: route.viewportRect,
          contentBounds: route.contentBounds
        )
      }
      assertNoInfiniteIdentityLoop(candidate)
      current = candidate.parent
    }
    return nil
  }

  package func dispatchPointerEvent(
    preferredRouteID: RouteID,
    identity: Identity,
    event: LocalPointerEvent
  ) -> Bool {
    if localPointerHandlerRegistry.dispatch(routeID: preferredRouteID, event: event) {
      return true
    }

    for fallbackRouteID in fallbackPrimaryRouteIDs(
      startingAt: identity,
      excluding: preferredRouteID
    ) {
      if localPointerHandlerRegistry.dispatch(routeID: fallbackRouteID, event: event) {
        return true
      }
    }

    return false
  }

  package func fallbackPrimaryRouteIDs(
    startingAt identity: Identity,
    excluding routeID: RouteID
  ) -> [RouteID] {
    var candidates: [RouteID] = []
    var nextIdentity: Identity? = identity

    while let current = nextIdentity {
      let candidateRouteID = primaryRouteID(for: current)
      if !strictlySameRouteID(candidateRouteID, routeID) {
        candidates.append(candidateRouteID)
      }
      nextIdentity = current.parent
    }

    return candidates
  }

  private func strictlySameRouteID(
    _ lhs: RouteID,
    _ rhs: RouteID
  ) -> Bool {
    lhs.identity == rhs.identity
      && lhs.kind == rhs.kind
      && lhs.ownerNodeID == rhs.ownerNodeID
  }

  package func isActivationIdentity(
    _ identity: Identity
  ) -> Bool {
    activationIdentity(for: identity) != nil
  }

  package func activationIdentity(
    for identity: Identity
  ) -> Identity? {
    if let containingIdentity = containingActivationIdentity(for: identity) {
      return containingIdentity
    }

    return localActionRegistry.snapshot().keys
      .filter { candidate in
        candidate.isDescendant(of: identity)
      }
      .min { lhs, rhs in
        let lhsDepth = identityDepth(lhs)
        let rhsDepth = identityDepth(rhs)
        if lhsDepth != rhsDepth {
          return lhsDepth < rhsDepth
        }
        return lhs < rhs
      }
  }

  package func containingActivationIdentity(
    for identity: Identity
  ) -> Identity? {
    var current: Identity? = identity
    while let candidate = current {
      if localActionRegistry.hasHandler(identity: candidate) {
        return candidate
      }
      assertNoInfiniteIdentityLoop(candidate)
      current = candidate.parent
    }
    return nil
  }

  /// Pointer-safe activation resolution. Like `activationIdentity(for:)` but the
  /// descendant fallback is constrained to handlers whose interaction region
  /// actually contains `location`. A pointer click must only activate a control
  /// it is physically over — the unconstrained descendant walk would otherwise
  /// reach *down* into a focused scope (e.g. an open sheet) and dispatch its sole
  /// handler when the click landed on suppressed background chrome, dismissing
  /// the overlay from an outside click (root `TODO.md`: "Presentation Lab
  /// overlays are sometimes unclosable; the background remains interactive").
  /// Keyboard activation keeps using the location-free `activationIdentity(for:)`
  /// because Enter/Space legitimately activates the focused scope's action.
  package func activationIdentity(
    for identity: Identity,
    underPointerAt location: PointerLocation
  ) -> Identity? {
    if let containingIdentity = containingActivationIdentity(for: identity) {
      return containingIdentity
    }

    return localActionRegistry.snapshot().keys
      .filter { candidate in
        candidate.isDescendant(of: identity)
          && handlerRegion(candidate, contains: location)
      }
      .min { lhs, rhs in
        let lhsDepth = identityDepth(lhs)
        let rhsDepth = identityDepth(rhs)
        if lhsDepth != rhsDepth {
          return lhsDepth < rhsDepth
        }
        return lhs < rhs
      }
  }

  private func handlerRegion(
    _ identity: Identity,
    contains location: PointerLocation
  ) -> Bool {
    latestSemanticSnapshot.interactionRegions.contains { region in
      region.identity == identity && region.contains(location)
    }
  }

  private func identityDepth(_ identity: Identity) -> Int {
    identity.description.filter { $0 == "/" }.count
  }

  package func shouldCapturePointer(
    routeID: RouteID
  ) -> Bool {
    interactionRegion(routeID: routeID)?.captureOnPress ?? false
  }

  package func assertNoInfiniteIdentityLoop(
    _: Identity
  ) {}
}
