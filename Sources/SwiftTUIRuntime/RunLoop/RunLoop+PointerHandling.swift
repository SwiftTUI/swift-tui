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
        || pointerInteraction.isRouting
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
      pointerInteraction.reset()
      setPressedIdentity(nil, transient: false)
      return
    }

    // Remember where the press began so a later drag can measure whether it
    // crossed the scroll-takeover threshold (see attemptDragThresholdTransfer…).
    pointerInteraction.beginPress(at: location)

    // A fresh press inside a flinging scroll view stops the fling (touch-to-stop),
    // and seeds the pan-velocity sampler so a drag that becomes a pan can measure
    // its release velocity from the press origin onward.
    cancelScrollMomentum(containing: hitTarget.region.identity)
    scrollPanVelocitySampler.reset(location: location.location, time: timestamp)

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
        pointerInteraction.capture(hitTarget.region.routeID)
      } else {
        // Non-capturing gestures like TapGesture still need the rest of the
        // pressed interaction stream so they can observe drag cancellation and
        // the eventual release.
        pointerInteraction.arm(hitTarget.region.routeID, usesPointerHandler: true)
      }
      setPressedIdentity(hitTarget.focusIdentity, transient: false)
      return
    }

    if let focusIdentity = hitTarget.focusIdentity,
      shouldClickFocus(focusIdentity, at: location)
    {
      _ = focusTracker.setFocus(to: focusIdentity)
      pointerInteraction.arm(hitTarget.region.routeID, usesPointerHandler: false)
      setPressedIdentity(focusIdentity, transient: false)
      return
    }
    pointerInteraction.clearRouting()
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
      pointerInteraction.reset()
      setPressedIdentity(nil, transient: false)
    }

    // Paired (not exact) region lookup: a captured gesture's `.up` must still
    // reach the recognizer when the control's chrome re-minted mid-gesture —
    // the same press/release straddle the armed path below tolerates. Without
    // it the release is dropped entirely: capture nils the armed route, so
    // there is no second chance.
    if let capturedRouteID = pointerInteraction.capturedRouteID,
      let region = pairedInteractionRegion(for: capturedRouteID)
    {
      _ = dispatchPointerEvent(
        preferredRouteID: region.routeID,
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
      // A captured *scroll* pan that releases with velocity flings; the `defer`
      // above then tears down the capture state but the fling lives on in the
      // run-loop-owned momentum controller, keyed by the route identity.
      beginScrollMomentumOnReleaseIfNeeded(
        routeIdentity: region.identity,
        releaseLocation: location,
        timestamp: timestamp
      )
      return
    }

    guard let armedRouteID = pointerInteraction.armedRouteID else {
      return
    }

    let hitTarget = hitTarget(at: location)
    // The armed route's region may have re-minted between press and release: an
    // owner `.id` churn (or any interaction that forces a re-resolve on the
    // mid-press frame) rebuilds the control's chrome with a fresh `ViewNodeID`,
    // so the region's `RouteID.ownerNodeID` changes while its stable identity and
    // kind do not. An exact match then fails and the release is dropped — a click
    // whose press/release straddle a churn stops dispatching. Pair by identity +
    // kind so the release still reaches the same logical control. The action
    // itself is registered at the control's stable identity, so dispatch below
    // is unaffected.
    guard let region = pairedInteractionRegion(for: armedRouteID) else {
      return
    }

    let pointerHandled = dispatchPointerEvent(
      preferredRouteID: armedRouteID,
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
    if pointerInteraction.armedRouteUsesPointerHandler {
      return
    }

    // Same owner-agnostic tolerance as the region lookup above: the release must
    // still be over the armed control, but a mid-press re-mint changes only the
    // hit region's `ownerNodeID`, not its identity, so compare owner-agnostically.
    guard let upRouteID = hitTarget?.region.routeID,
      upRouteID.pairsIgnoringOwner(with: armedRouteID)
    else {
      return
    }

    let focusedIdentity =
      hitTarget?.focusIdentity
      ?? focusIdentity(for: region.identity)
    // Both resolutions are location-constrained: a pointer release may only
    // activate a handler physically under the cursor. The walk-up would
    // otherwise reach actions registered at identities whose subtree spans
    // more screen than the control itself (the TabView strip action parents
    // the whole tab page — see containingActivationIdentity(for:underPointerAt:)).
    let actionIdentity =
      hitTarget.flatMap {
        containingActivationIdentity(for: $0.region.identity, underPointerAt: location)
      }
      ?? focusedIdentity.flatMap { activationIdentity(for: $0, underPointerAt: location) }

    if let actionIdentity {
      let invalidationsBeforeDispatch = schedulerPendingInvalidations()
      let handled = localActionRegistry.dispatch(identity: actionIdentity)
      if handled {
        recordFollowUpInvalidation(
          for: actionIdentity,
          schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
        )
      }
    }
  }

  package func handleMouseMove(
    location: PointerLocation,
    timestamp: MonotonicInstant = .now()
  ) {
    updatePointerHover(at: location)

    guard pointerInteraction.armedRouteID != nil else {
      return
    }
    if pointerInteraction.armedRouteUsesPointerHandler,
      let armedRouteID = pointerInteraction.armedRouteID,
      let region = pairedInteractionRegion(for: armedRouteID)
    {
      // A churn frame mid-press re-minted the armed control's chrome; the
      // paired region carries the fresh route, so adopt it for the rest of
      // the interaction.
      if region.routeID != armedRouteID {
        pointerInteraction.rekeyArmedRoute(to: region.routeID)
      }
      let handled = dispatchPointerEvent(
        preferredRouteID: region.routeID,
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

    // A drag that begins on an inner control but travels far enough along a
    // scrollable ancestor's axis hands the gesture to that scroll view (the
    // control is cancelled and never activates), matching SwiftUI.
    if attemptDragThresholdTransferToAncestorScroll(at: location, timestamp: timestamp) {
      return
    }

    if let capturedRouteID = pointerInteraction.capturedRouteID,
      let region = pairedInteractionRegion(for: capturedRouteID)
    {
      // A churn frame mid-gesture re-minted the captured control's chrome;
      // adopt the paired region's fresh route so later events match exactly.
      if region.routeID != capturedRouteID {
        pointerInteraction.rekeyCapturedRoute(to: region.routeID)
      }
      // Sample the captured pan so a release can estimate fling velocity. Cheap
      // and harmless for non-scroll captured routes (consumed only at a scroll
      // route's `.up`).
      recordScrollPanSample(location: location, timestamp: timestamp)
      _ = dispatchPointerEvent(
        preferredRouteID: region.routeID,
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
      // A wheel notch is an explicit reposition: cancel any fling on that route
      // so the discrete scroll wins instead of fighting the decay.
      cancelScrollMomentum(containing: scrollRoute.identity)
      let routeID = primaryRouteID(
        for: scrollRoute.identity,
        ownerNodeID: scrollRoute.viewNodeID
      )
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
          namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
          timestamp: timestamp
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
