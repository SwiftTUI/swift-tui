import Core
import View

extension RunLoop {
  package struct HitTarget {
    var region: InteractionRegion
    var focusIdentity: Identity?
  }

  package func handleMouseEvent(
    _ mouseEvent: MouseEvent
  ) {
    switch mouseEvent.kind {
    case .down(let button):
      handleMouseDown(button, location: mouseEvent.location)
    case .up(let button):
      handleMouseUp(button, location: mouseEvent.location)
    case .moved:
      handleMouseMove(location: mouseEvent.location)
    case .dragged(let button):
      handleMouseDrag(button, location: mouseEvent.location)
    case .scrolled(let deltaX, let deltaY):
      handleMouseScroll(deltaX: deltaX, deltaY: deltaY, location: mouseEvent.location)
    }
  }

  package func shouldScheduleFrame(
    for mouseEvent: MouseEvent
  ) -> Bool {
    switch mouseEvent.kind {
    case .moved:
      return armedPointerRouteID != nil || capturedPointerRouteID != nil
    case .down, .up, .dragged:
      return true
    case .scrolled:
      return false
    }
  }

  package func handleMouseDown(
    _ button: MouseButton,
    location: PointerLocation
  ) {
    guard button == .primary else {
      return
    }

    let hitTarget = hitTarget(at: location)

    guard let hitTarget else {
      armedPointerRouteID = nil
      armedPointerRouteUsesPointerHandler = false
      capturedPointerRouteID = nil
      setPressedIdentity(nil, transient: false)
      return
    }

    let pointerEvent = LocalPointerEvent(
      kind: .down(.primary),
      location: location,
      targetRect: hitTarget.region.rect,
      scrollContext: scrollContext(for: hitTarget.region.identity)
    )

    let customHandled = dispatchPointerEvent(
      preferredRouteID: hitTarget.region.routeID,
      identity: hitTarget.region.identity,
      event: pointerEvent
    )

    if customHandled {
      if let focusIdentity = hitTarget.focusIdentity,
        shouldClickFocus(focusIdentity, at: location)
      {
        _ = focusTracker.setFocus(to: focusIdentity)
      }
      if shouldCapturePointer(routeID: hitTarget.region.routeID) {
        capturedPointerRouteID = hitTarget.region.routeID
        armedPointerRouteID = nil
        armedPointerRouteUsesPointerHandler = false
      } else {
        capturedPointerRouteID = nil
        // Non-capturing gestures like TapGesture still need the rest of the
        // pressed interaction stream so they can observe drag cancellation and
        // the eventual release.
        armedPointerRouteID = hitTarget.region.routeID
        armedPointerRouteUsesPointerHandler = true
      }
      setPressedIdentity(hitTarget.focusIdentity, transient: false)
      return
    }

    capturedPointerRouteID = nil
    if let focusIdentity = hitTarget.focusIdentity,
      shouldClickFocus(focusIdentity, at: location)
    {
      _ = focusTracker.setFocus(to: focusIdentity)
      armedPointerRouteID = hitTarget.region.routeID
      armedPointerRouteUsesPointerHandler = false
      setPressedIdentity(focusIdentity, transient: false)
      return
    }
    armedPointerRouteID = nil
    armedPointerRouteUsesPointerHandler = false
    setPressedIdentity(nil, transient: false)
  }

  package func handleMouseUp(
    _ button: MouseButton,
    location: PointerLocation
  ) {
    guard button == .primary else {
      return
    }

    defer {
      capturedPointerRouteID = nil
      armedPointerRouteID = nil
      armedPointerRouteUsesPointerHandler = false
      setPressedIdentity(nil, transient: false)
    }

    if let capturedPointerRouteID,
      let region = interactionRegion(routeID: capturedPointerRouteID)
    {
      _ = dispatchPointerEvent(
        preferredRouteID: capturedPointerRouteID,
        identity: region.identity,
        event: .init(
          kind: .up(.primary),
          location: location,
          targetRect: region.rect,
          scrollContext: scrollContext(for: region.identity)
        )
      )
      return
    }

    guard let armedPointerRouteID else {
      return
    }

    let hitTarget = hitTarget(at: location)
    guard let region = interactionRegion(routeID: armedPointerRouteID) else {
      return
    }

    let pointerHandled = dispatchPointerEvent(
      preferredRouteID: armedPointerRouteID,
      identity: region.identity,
      event: .init(
        kind: .up(.primary),
        location: location,
        targetRect: region.rect,
        scrollContext: scrollContext(for: region.identity)
      )
    )
    if pointerHandled {
      return
    }
    if armedPointerRouteUsesPointerHandler {
      return
    }

    guard hitTarget?.region.routeID == armedPointerRouteID else {
      return
    }

    let focusedIdentity =
      hitTarget?.focusIdentity
      ?? focusIdentity(for: region.identity)

    if let focusedIdentity {
      let handled = localActionRegistry.dispatch(identity: focusedIdentity)
      if handled,
        let identity = localActionRegistry.followUpInvalidationIdentity(for: focusedIdentity)
      {
        postActionInvalidationIdentities.insert(identity)
      }
    }
  }

  package func handleMouseMove(
    location: PointerLocation
  ) {
    guard armedPointerRouteID != nil else {
      return
    }
    if armedPointerRouteUsesPointerHandler,
      let armedPointerRouteID,
      let region = interactionRegion(routeID: armedPointerRouteID)
    {
      let handled = dispatchPointerEvent(
        preferredRouteID: armedPointerRouteID,
        identity: region.identity,
        event: .init(
          kind: .dragged(.primary),
          location: location,
          targetRect: region.rect,
          scrollContext: scrollContext(for: region.identity)
        )
      )
      if handled {
        return
      }
    }

    updateArmedPointerState(at: location)
  }

  package func handleMouseDrag(
    _ button: MouseButton,
    location: PointerLocation
  ) {
    guard button == .primary else {
      return
    }

    if let capturedPointerRouteID,
      let region = interactionRegion(routeID: capturedPointerRouteID)
    {
      _ = dispatchPointerEvent(
        preferredRouteID: capturedPointerRouteID,
        identity: region.identity,
        event: .init(
          kind: .dragged(.primary),
          location: location,
          targetRect: region.rect,
          scrollContext: scrollContext(for: region.identity)
        )
      )
      return
    }

    updateArmedPointerState(at: location)
  }

  package func handleMouseScroll(
    deltaX: Int,
    deltaY: Int,
    location: PointerLocation
  ) {
    // Scroll events should not move keyboard focus — the scroll target
    // is resolved independently via scrollTarget(at:).
    if let scrollRoute = scrollTarget(at: location, deltaX: deltaX, deltaY: deltaY) {
      let routeID = primaryRouteID(for: scrollRoute.identity)
      let handled = dispatchPointerEvent(
        preferredRouteID: routeID,
        identity: scrollRoute.identity,
        event: .init(
          kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
          location: location,
          targetRect: scrollRoute.viewportRect,
          scrollContext: .init(
            viewportRect: scrollRoute.viewportRect,
            contentBounds: scrollRoute.contentBounds
          )
        )
      )
      if handled {
        scheduler.requestInvalidation(
          of: scrollPointerInvalidationIdentities(for: scrollRoute.identity)
        )
      }
    } else if let hitTarget = hitTarget(at: location) {
      let handled = dispatchPointerEvent(
        preferredRouteID: hitTarget.region.routeID,
        identity: hitTarget.region.identity,
        event: .init(
          kind: .scrolled(deltaX: deltaX, deltaY: deltaY),
          location: location,
          targetRect: hitTarget.region.rect,
          scrollContext: scrollContext(for: hitTarget.region.identity)
        )
      )
      if handled {
        scheduler.requestInvalidation(
          of: scrollPointerInvalidationIdentities(for: hitTarget.region.identity)
        )
      }
    }
  }

  private func scrollPointerInvalidationIdentities(
    for identity: Identity
  ) -> Set<Identity> {
    var identities: Set<Identity> = [identity]
    var parent = identity.parent
    while let current = parent {
      guard !current.components.isEmpty else {
        break
      }
      if current == rootIdentity, identities.count > 1 {
        break
      }
      identities.insert(current)
      parent = current.parent
    }
    return identities
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
        .filter({ $0.rect.contains(location.cell) })
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
      if candidateRouteID != routeID {
        candidates.append(candidateRouteID)
      }
      nextIdentity = current.parent
    }

    return candidates
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

  package func updateArmedPointerState(
    at location: PointerLocation
  ) {
    guard let armedPointerRouteID else {
      return
    }

    let currentRouteID = hitTarget(at: location)?.region.routeID
    if currentRouteID == armedPointerRouteID,
      let region = interactionRegion(routeID: armedPointerRouteID)
    {
      setPressedIdentity(focusIdentity(for: region.identity), transient: false)
    } else {
      setPressedIdentity(nil, transient: false)
    }
  }

  package func setPressedIdentity(
    _ identity: Identity?,
    transient: Bool
  ) {
    let previousPressedIdentity = pressedIdentity
    pressedIdentity = identity
    transientPressedIdentity = transient ? identity : nil

    guard previousPressedIdentity != identity else {
      return
    }

    var invalidatedIdentities: Set<Identity> = []
    if let previousPressedIdentity {
      invalidatedIdentities.insert(previousPressedIdentity)
    }
    if let identity {
      invalidatedIdentities.insert(identity)
    }
    if !invalidatedIdentities.isEmpty {
      scheduler.requestInvalidation(of: invalidatedIdentities)
    }
  }

  package func assertNoInfiniteIdentityLoop(
    _: Identity
  ) {}
}
