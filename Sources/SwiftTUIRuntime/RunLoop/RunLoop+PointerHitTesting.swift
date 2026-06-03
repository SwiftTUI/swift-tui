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
    localActionRegistry.hasHandler(identity: identity)
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
