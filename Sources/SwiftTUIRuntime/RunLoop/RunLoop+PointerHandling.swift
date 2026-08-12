import SwiftTUICore
import SwiftTUIViews

extension RunLoop {
  package func handleMouseEvent(
    _ mouseEvent: MouseEvent
  ) {
    lastPointerLocation = mouseEvent.location
    // Deliberate pointer actions supersede the pending keyboard traversal
    // record (passive hover moves do not — they can race the frame that
    // resolves the traversal's landing).
    switch mouseEvent.kind {
    case .down, .up, .dragged, .scrolled:
      pendingFocusTraversal = nil
    case .moved:
      break
    }
    // A fresh press or a deliberate pan supersedes any click-restore record
    // from a previous press (the record must only ever describe the latest
    // press). `.up` keeps it: the frame that decides whether the clicked
    // region survived lands after the release.
    switch mouseEvent.kind {
    case .down, .dragged, .scrolled:
      pendingClickFocusRestore = nil
    case .up, .moved:
      break
    }
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
    // crossed the scroll-takeover threshold (see attemptDragThresholdTransfer…),
    // and the focused values it began under so the release activation can
    // dispatch against the focus state the user acted on (the click-to-focus
    // below moves focus before `.up` fires the action).
    pointerInteraction.beginPress(at: location, focusedValues: currentFocusedValues)

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

    let dispatch = dispatchPointerEventResolvingHandler(
      preferredRouteID: hitTarget.region.routeID,
      identity: hitTarget.region.identity,
      event: pointerEvent
    )

    if dispatch.outcome.wantsPointerStream {
      if let focusIdentity = hitTarget.focusIdentity,
        shouldClickFocus(focusIdentity, at: location)
      {
        recordClickFocusRestore(landing: focusIdentity)
        _ = focusTracker.setFocus(to: focusIdentity)
      }
      if shouldCapturePointer(routeID: hitTarget.region.routeID) {
        pointerInteraction.capture(
          hitTarget.region.routeID,
          pointerHandlerIdentity: dispatch.handlerRouteID?.identity
        )
      } else {
        // Non-capturing gestures like TapGesture still need the rest of the
        // pressed interaction stream so they can observe drag cancellation and
        // the eventual release.
        pointerInteraction.arm(
          hitTarget.region.routeID,
          usesPointerHandler: true,
          pointerHandlerIdentity: dispatch.handlerRouteID?.identity
        )
      }
      setPressedIdentity(hitTarget.focusIdentity, transient: false)
      return
    }

    if let focusIdentity = hitTarget.focusIdentity,
      shouldClickFocus(focusIdentity, at: location)
    {
      recordClickFocusRestore(landing: focusIdentity)
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
      let dispatchOutcome = pointerInteraction.releaseOutcome(
        combining: dispatchPointerEvent(
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
      )
      // A drag recognizer captures on press so it can follow motion outside
      // the original cell. If it never crosses its minimum distance, its
      // release fails instead of claiming the click. Let a control at that
      // same route activate normally. An ordinary or high-priority recognized
      // drag claims the release and suppresses activation; a simultaneous drag
      // only observes it and leaves the control eligible for activation.
      if dispatchOutcome != .claimed,
        region.contains(location),
        let actionIdentity = containingActivationIdentity(
          for: region.identity,
          underPointerAt: location
        )
      {
        dispatchReleaseActivation(
          identity: actionIdentity,
          hitOwnerNodeID: region.routeID.ownerNodeID
        )
      }
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

    let dispatchOutcome = pointerInteraction.releaseOutcome(
      combining: dispatchPointerEvent(
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
    )
    if dispatchOutcome == .claimed {
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
      dispatchReleaseActivation(
        identity: actionIdentity,
        hitOwnerNodeID: hitTarget?.region.routeID.ownerNodeID
      )
    }
  }

  /// Records the pre-press focus as the restore target for a click-focus move
  /// about to land on `landing`, so a landed region that vanishes on its first
  /// rendered frame (a control revoking its own focusability as a consequence
  /// of receiving focus) returns focus whence it came. See
  /// `RunLoop.pendingClickFocusRestore`.
  private func recordClickFocusRestore(landing: Identity) {
    guard let origin = focusTracker.currentFocusIdentity, origin != landing else {
      pendingClickFocusRestore = nil
      return
    }
    pendingClickFocusRestore = PendingClickFocusRestore(
      landedIdentity: landing,
      originIdentity: origin
    )
  }

  private func dispatchReleaseActivation(
    identity: Identity,
    hitOwnerNodeID: ViewNodeID?
  ) {
    let invalidationsBeforeDispatch = schedulerPendingInvalidations()
    // Dispatch under the press-time focused values: the press moved focus
    // (click-to-focus) before this release, and a frame in between can have
    // re-seated focus again (a control disabling itself once the publisher
    // lost focus drops its region), so the live set here can describe a
    // control the user never acted on. See
    // `PointerInteractionState.pressFocusedValues`.
    let handled = LiveFocusedValuesRegistry.withFocusedValuesOverride(
      pointerInteraction.pressFocusedValues
    ) {
      dispatchActivationAction(
        identity: identity,
        hitOwnerNodeID: hitOwnerNodeID
      )
    }
    if handled {
      recordFollowUpInvalidation(
        for: identity,
        schedulerInvalidationsBeforeDispatch: invalidationsBeforeDispatch
      )
    }
  }

  /// Runs the activation for `identity`, preferring the handler recorded on
  /// the hit region's owner node. Duplicate-ID occurrences share one
  /// `Identity` in the last-write-wins action registry, so identity dispatch
  /// alone runs the wrong occurrence's closure for every duplicate but the
  /// last-registered one. Regions without an owner and ancestor-walked
  /// activation identities (whose handler lives above the hit node) keep the
  /// identity-keyed dispatch.
  private func dispatchActivationAction(
    identity: Identity,
    hitOwnerNodeID: ViewNodeID?
  ) -> Bool {
    if let hitOwnerNodeID,
      let registration = renderer.viewGraph.occurrenceActionRegistration(
        ownerNodeID: hitOwnerNodeID,
        identity: identity
      )
    {
      return registration.handler()
    }
    return localActionRegistry.dispatch(identity: identity)
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
      let dispatchOutcome = dispatchPointerEvent(
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
      if dispatchOutcome.wantsPointerStream {
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
    if var scrollRoute = scrollTarget(at: location, deltaX: deltaX, deltaY: deltaY) {
      var refusedIdentities: Set<Identity> = []
      while true {
        // A wheel notch is an explicit reposition: cancel any fling on that route
        // so the discrete scroll wins instead of fighting the decay.
        cancelScrollMomentum(containing: scrollRoute.identity)
        let routeID = primaryRouteID(
          for: scrollRoute.identity,
          ownerNodeID: scrollRoute.viewNodeID
        )
        let dispatchOutcome = dispatchPointerEvent(
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
        if dispatchOutcome.wantsPointerStream {
          scheduler.requestInvalidation(
            of: scrollPointerInvalidationIdentities(for: scrollRoute.identity)
          )
          break
        }
        // The route refused the delta (clamped at its edge, or the delta
        // doesn't match its scrollable axis). Chain outward to the
        // next-innermost spatially enclosing route that can consume it.
        refusedIdentities.insert(scrollRoute.identity)
        guard
          let enclosingRoute = scrollTarget(
            at: location,
            excluding: refusedIdentities,
            deltaX: deltaX,
            deltaY: deltaY
          )
        else {
          break
        }
        scrollRoute = enclosingRoute
      }
    } else if let hitTarget = hitTarget(at: location) {
      let dispatchOutcome = dispatchPointerEvent(
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
      if dispatchOutcome.wantsPointerStream {
        scheduler.requestInvalidation(
          of: scrollPointerInvalidationIdentities(for: hitTarget.region.identity)
        )
      }
    }
  }

  /// The invalidation a consumed pointer scroll requests: the route identity
  /// alone (scroll-latency R1.6, plan 2026-08-08-001).
  ///
  /// The dispatch-side request is the scheduling backstop for scroll bindings
  /// whose writes are not state-tracked (a `Binding(get:set:)` over external
  /// storage): `.scrolled` never schedules an input frame
  /// (``shouldScheduleFrame(for:)``), so without this request nothing would
  /// render the moved offset. For tracked bindings it coalesces with the
  /// write's own reader-attributed invalidation of the same identity.
  ///
  /// No ancestor spine. The historical climb inserted every lexical ancestor
  /// below the root, but ancestor membership added no soundness: every
  /// layout-tier reuse gate already treats the route's ancestors
  /// conservatively (has-invalidated-descendant and
  /// affects-indexed-source-within denial), and the damage resolver diffs
  /// draw trees, not the seed set. Membership only re-ran the spine
  /// containers' bodies at the resolve tier (dirty=5 vs dirty=1 per notch at
  /// the 10k vehicle) and defeated pointer-fast equivalence above the route
  /// (removal measured −2.9% pipeline p50, gate-real). Route-only also
  /// matches every other scroll entry path — keyboard handlers, momentum
  /// registry `scrollBy`, `scrollTo`/reveal, and indicator drags all
  /// invalidate through the binding write alone — and stops minting ghost
  /// lexical ancestors that own no nodes.
  private func scrollPointerInvalidationIdentities(
    for identity: Identity
  ) -> Set<Identity> {
    [identity]
  }

}
