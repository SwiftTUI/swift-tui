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

  /// Region lookup for an event stream that may straddle a re-mint. A route
  /// captured or armed at press time carries the `ownerNodeID` of the node
  /// that minted it; if a churn frame rebuilds that node mid-interaction, the
  /// snapshot's region for the same logical control carries a fresh owner and
  /// an exact match fails. Resolve exactly first, then pair by identity + kind
  /// (topmost `hitTestOrder` wins, deterministically). The returned region's
  /// own `routeID` is the fresh one — callers that hold the stale route across
  /// further events should re-key their stored state to it.
  package func pairedInteractionRegion(
    for routeID: RouteID
  ) -> InteractionRegion? {
    if let exact = interactionRegion(routeID: routeID) {
      return exact
    }
    return latestSemanticSnapshot.interactionRegions
      .filter { $0.routeID.pairsIgnoringOwner(with: routeID) }
      .max { $0.hitTestOrder < $1.hitTestOrder }
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
      // Pairing (not strict) exclusion: the candidate for the starting
      // identity is the preferred route minus its owner, and dispatch resolves
      // both to the same handler — including it would probe that handler a
      // second time with the same event.
      if !candidateRouteID.pairsIgnoringOwner(with: routeID) {
        candidates.append(candidateRouteID)
      }
      nextIdentity = current.parent
    }

    return candidates
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

  /// Focus-driven activation resolution: walks up from the focused identity
  /// to the action of the control that *owns* it, stopping at the first
  /// ancestor that is itself an independently focusable control (it mints its
  /// own focus region). Crossing such a boundary would let Enter/Space on a
  /// focused control activate a *different* control the user never focused —
  /// `TabView` registers its strip action at the control identity that also
  /// parents the whole tab page, so the unbounded walk turned Enter in any
  /// focused page control (e.g. a text field) into a strip activation,
  /// dropping down the overflow menu whenever the selected tab sat in the
  /// overflow set. Intermediate wrapper identities that mint no focus region
  /// are still walked through, so an action registered above its control's
  /// focus region keeps resolving.
  package func containingActivationIdentity(
    for identity: Identity
  ) -> Identity? {
    var current: Identity? = identity
    while let candidate = current {
      if candidate != identity, mintsFocusRegion(candidate) {
        return nil
      }
      if localActionRegistry.hasHandler(identity: candidate) {
        return candidate
      }
      assertNoInfiniteIdentityLoop(candidate)
      current = candidate.parent
    }
    return nil
  }

  private func mintsFocusRegion(_ identity: Identity) -> Bool {
    latestSemanticSnapshot.focusRegions.contains { $0.identity == identity }
  }

  /// Pointer-safe variant of `containingActivationIdentity(for:)`: an ancestor
  /// handler whose interaction regions exist in the snapshot but do not contain
  /// `location` is skipped instead of activated. A control can register its
  /// action at an identity whose *subtree* spans far more screen than the
  /// control itself — `TabView` registers its strip action at the control
  /// identity that also parents the whole tab page, and deliberately pins the
  /// root's interaction rect to zero (`tabViewSemanticMetadata`) so no pointer
  /// location is ever inside it. The unconstrained walk-up turned a click on
  /// unclaimed page background into a strip activation, dropping down the
  /// overflow menu whenever the selected tab sat in the overflow set. A handler
  /// identity that mints no region at all keeps the location-free behavior —
  /// there is no geometric evidence to veto it. Keyboard activation keeps using
  /// the location-free walk: Enter/Space legitimately activates the focused
  /// scope's action.
  package func containingActivationIdentity(
    for identity: Identity,
    underPointerAt location: PointerLocation
  ) -> Identity? {
    var current: Identity? = identity
    while let candidate = current {
      if localActionRegistry.hasHandler(identity: candidate),
        handlerRegionPermitsPointerActivation(candidate, at: location)
      {
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
    if let containingIdentity = containingActivationIdentity(
      for: identity,
      underPointerAt: location
    ) {
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

  /// A pointer activation candidate is vetoed only by geometric evidence:
  /// regions minted for the candidate identity that all exclude `location`.
  private func handlerRegionPermitsPointerActivation(
    _ identity: Identity,
    at location: PointerLocation
  ) -> Bool {
    var mintsRegion = false
    for region in latestSemanticSnapshot.interactionRegions
    where region.identity == identity {
      if region.contains(location) {
        return true
      }
      mintsRegion = true
    }
    return !mintsRegion
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
