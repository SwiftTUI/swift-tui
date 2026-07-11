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

    // Paired lookup: a fallback hover route from the ancestor walk carries no
    // `ownerNodeID`, while every snapshot region carries one, so the exact
    // probe alone would never find its region.
    guard let hoveredRouteID,
      let hoveredRegion = pairedInteractionRegion(for: hoveredRouteID)
    else {
      clearPointerHover()
      return
    }

    let localLocation = Point(
      x: location.location.x - Double(hoveredRegion.rect.origin.x),
      y: location.location.y - Double(hoveredRegion.rect.origin.y)
    )

    // Owner-agnostic continuity: a churn frame that re-minted the hovered
    // control's chrome changes only the route's `ownerNodeID`. The pointer
    // never left the logical control, so re-key to the fresh route and keep
    // reporting `.moved` — an exact comparison would fabricate an exit/enter
    // flicker on every mid-hover re-mint.
    if let currentRouteID = hoveredPointerRouteID,
      currentRouteID.pairsIgnoringOwner(with: hoveredRouteID)
    {
      hoveredPointerRouteID = hoveredRouteID
      dispatchHoverSupersedingTraversalOnMutation(
        routeID: hoveredRouteID,
        phase: .moved(localLocation)
      )
    } else {
      clearPointerHover()
      hoveredPointerRouteID = hoveredRouteID
      dispatchHoverSupersedingTraversalOnMutation(
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
    dispatchHoverSupersedingTraversalOnMutation(
      routeID: hoveredPointerRouteID,
      phase: .exited
    )
  }

  /// Dispatches a hover phase and, when a handler mutated state, drops the
  /// pending keyboard-traversal record. Passive pointer moves deliberately
  /// keep that record (they can race the frame resolving the traversal's
  /// landing) — but a hover handler that requested an invalidation makes
  /// this input a deliberate mutation like a click: a focus region removed
  /// by it vanished because of the hover, not the traversal, so the
  /// traversal must not continue onto the region's document-order neighbor.
  private func dispatchHoverSupersedingTraversalOnMutation(
    routeID: RouteID,
    phase: HoverPhase
  ) {
    let invalidationsBeforeDispatch = schedulerPendingInvalidations()
    localPointerHandlerRegistry.dispatchHover(
      routeID: routeID,
      phase: phase
    )
    if schedulerPendingInvalidations() != invalidationsBeforeDispatch {
      pendingFocusTraversal = nil
    }
  }

  package func pointerHoverRouteID(
    startingAt identity: Identity,
    preferredRouteID: RouteID
  ) -> RouteID? {
    // Pairing (not exact) lookups: the hit region's route carries the placed
    // node's owner while the handler registered under its evaluation node's —
    // the two legitimately differ (and diverge further across re-mints), so
    // an exact registry probe would miss live handlers.
    if localPointerHandlerRegistry.hasHoverHandler(pairingWith: preferredRouteID) {
      return preferredRouteID
    }

    return fallbackPrimaryRouteIDs(
      startingAt: identity,
      excluding: preferredRouteID
    )
    .first { routeID in
      localPointerHandlerRegistry.hasHoverHandler(pairingWith: routeID)
    }
  }

  package func updateArmedPointerState(
    at location: PointerLocation
  ) {
    guard let armedRouteID = pointerInteraction.armedRouteID else {
      return
    }

    // Owner-agnostic: pressed-state feedback must survive a mid-press re-mint
    // of the armed control's chrome, exactly like the release pairing.
    let currentRouteID = hitTarget(at: location)?.region.routeID
    if let currentRouteID,
      currentRouteID.pairsIgnoringOwner(with: armedRouteID),
      let region = pairedInteractionRegion(for: armedRouteID)
    {
      if region.routeID != armedRouteID {
        pointerInteraction.rekeyArmedRoute(to: region.routeID)
      }
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
