import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  package func handleMouseEvent(
    _ mouseEvent: MouseEvent
  ) {
    switch mouseEvent.kind {
    case .down(let button):
      handleMouseDown(button, location: mouseEvent.location, timestamp: mouseEvent.timestamp)
    case .up(let button):
      handleMouseUp(button, location: mouseEvent.location, timestamp: mouseEvent.timestamp)
    case .moved:
      handleMouseMove(location: mouseEvent.location, timestamp: mouseEvent.timestamp)
    case .dragged(let button):
      handleMouseDrag(button, location: mouseEvent.location, timestamp: mouseEvent.timestamp)
    case .scrolled(let deltaX, let deltaY):
      handleMouseScroll(
        deltaX: deltaX,
        deltaY: deltaY,
        location: mouseEvent.location,
        timestamp: mouseEvent.timestamp
      )
    }
  }

  package func shouldScheduleFrame(
    for mouseEvent: MouseEvent
  ) -> Bool {
    switch mouseEvent.kind {
    case .moved:
      return localPointerHandlerRegistry.hasHoverSubscribers
        || armedPointerRouteID != nil || capturedPointerRouteID != nil
    case .down, .up, .dragged:
      return true
    case .scrolled:
      return false
    }
  }

  package func handleMouseDown(
    _ button: MouseButton,
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
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
      scrollContext: scrollContext(for: hitTarget.region.identity),
      namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
      timestamp: timestamp
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
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
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
          scrollContext: scrollContext(for: region.identity),
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
          timestamp: timestamp
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
        scrollContext: scrollContext(for: region.identity),
        namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
        timestamp: timestamp
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
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
  ) {
    updatePointerHover(at: location)

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
          scrollContext: scrollContext(for: region.identity),
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
          timestamp: timestamp
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
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
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
          scrollContext: scrollContext(for: region.identity),
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
          timestamp: timestamp
        )
      )
      return
    }

    updateArmedPointerState(at: location)
  }

  package func handleMouseScroll(
    deltaX: Int,
    deltaY: Int,
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
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
          ),
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
          timestamp: timestamp
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
          scrollContext: scrollContext(for: hitTarget.region.identity),
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces
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

}
