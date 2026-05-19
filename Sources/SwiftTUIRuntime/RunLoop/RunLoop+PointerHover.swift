import SwiftTUICore

extension RunLoop {
  package func updatePointerHover(
    at location: PointerLocation
  ) {
    guard localPointerHandlerRegistry.hasHoverSubscribers else {
      clearPointerHover()
      return
    }

    let hoveredRouteID =
      hitTarget(at: location)
      .flatMap { hitTarget in
        pointerHoverRouteID(
          startingAt: hitTarget.region.identity,
          preferredRouteID: hitTarget.region.routeID
        )
      }

    guard let hoveredRouteID,
      let hoveredRegion = interactionRegion(routeID: hoveredRouteID)
    else {
      clearPointerHover()
      return
    }

    let localLocation = Point(
      x: location.location.x - Double(hoveredRegion.rect.origin.x),
      y: location.location.y - Double(hoveredRegion.rect.origin.y)
    )

    if hoveredPointerRouteID == hoveredRouteID {
      localPointerHandlerRegistry.dispatchHover(
        routeID: hoveredRouteID,
        phase: .moved(localLocation)
      )
    } else {
      clearPointerHover()
      hoveredPointerRouteID = hoveredRouteID
      localPointerHandlerRegistry.dispatchHover(
        routeID: hoveredRouteID,
        phase: .entered(localLocation)
      )
    }
  }

  package func clearPointerHover() {
    guard let hoveredPointerRouteID else {
      return
    }
    self.hoveredPointerRouteID = nil
    localPointerHandlerRegistry.dispatchHover(
      routeID: hoveredPointerRouteID,
      phase: .exited
    )
  }

  package func pointerHoverRouteID(
    startingAt identity: Identity,
    preferredRouteID: RouteID
  ) -> RouteID? {
    if localPointerHandlerRegistry.hasHoverHandler(routeID: preferredRouteID) {
      return preferredRouteID
    }

    return fallbackPrimaryRouteIDs(
      startingAt: identity,
      excluding: preferredRouteID
    )
    .first { routeID in
      localPointerHandlerRegistry.hasHoverHandler(routeID: routeID)
    }
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
}
