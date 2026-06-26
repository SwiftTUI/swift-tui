import SwiftTUICore

/// Minimum drag distance, in cells, along a scrollable axis before a press that
/// began on an inner control is handed to an ancestor scroll view. Acts as a
/// deadzone so taps and small jitters still activate the control.
private let scrollTakeoverThreshold = 2

extension RunLoop {
  /// If the active press is *armed* on an inner control and the drag has crossed
  /// the takeover threshold along a scrollable ancestor's dominant axis, cancel
  /// the control and begin a captured pan on that scroll view. Returns `true`
  /// when the gesture was transferred.
  ///
  /// Only *armed* routes yield: captured routes (sliders, scroll indicators, and
  /// the scroll body itself) own their gesture for its whole lifetime, matching
  /// SwiftUI where a slider drag never turns into a scroll. The probe is
  /// restricted to the drag's dominant axis so a vertical scroll view ignores a
  /// horizontal drag and vice versa.
  func attemptDragThresholdTransferToAncestorScroll(
    at location: PointerLocation,
    timestamp: MonotonicInstant
  ) -> Bool {
    guard pointerInteraction.capturedRouteID == nil,
      pointerInteraction.armedRouteID != nil,
      let dragStartLocation = pointerInteraction.dragStartLocation
    else {
      return false
    }

    let deltaX = location.cell.x - dragStartLocation.cell.x
    let deltaY = location.cell.y - dragStartLocation.cell.y
    let verticalDominant = abs(deltaY) >= abs(deltaX)
    let dominantDelta = verticalDominant ? deltaY : deltaX
    guard abs(dominantDelta) >= scrollTakeoverThreshold else {
      return false
    }

    // Probe only the dominant axis so the scroll view must actually scroll the
    // direction the user is dragging to claim the gesture.
    let probeX = verticalDominant ? 0 : deltaX
    let probeY = verticalDominant ? deltaY : 0
    guard
      let scrollRoute = scrollTarget(at: dragStartLocation, deltaX: probeX, deltaY: probeY)
    else {
      return false
    }

    // Cancel the armed control (it must not activate when the gesture ends) and
    // capture the scroll view instead, anchoring the pan at the *press origin*
    // and replaying the drag to the current location. Anchoring at the origin
    // (not the takeover point) keeps the full drag distance — important because
    // the run loop coalesces drag bursts, so a fast drag arrives as one event
    // whose whole delta must pan rather than be swallowed as a deadzone. The
    // `capture(_:)` transition clears the armed route as it takes the capture.
    setPressedIdentity(nil, transient: false)
    let scrollRouteID = primaryRouteID(
      for: scrollRoute.identity,
      ownerNodeID: scrollRoute.viewNodeID
    )
    pointerInteraction.capture(scrollRouteID)
    // Seed the pan-velocity sampler for the handed-off pan so a quick flick after
    // takeover can fling. The two synthetic events below share `timestamp`
    // (Δt = 0), which the sampler ignores; real drags afterward add timed samples.
    scrollPanVelocitySampler.reset(location: dragStartLocation.location, time: timestamp)
    scrollPanVelocitySampler.record(location: location.location, time: timestamp)
    let scrollContext = LocalPointerScrollContext(
      viewportRect: scrollRoute.viewportRect,
      contentBounds: scrollRoute.contentBounds
    )
    _ = dispatchPointerEvent(
      preferredRouteID: scrollRouteID,
      identity: scrollRoute.identity,
      event: .init(
        kind: .down(.primary),
        location: dragStartLocation,
        targetRect: scrollRoute.viewportRect,
        scrollContext: scrollContext,
        namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
        timestamp: timestamp
      )
    )
    _ = dispatchPointerEvent(
      preferredRouteID: scrollRouteID,
      identity: scrollRoute.identity,
      event: .init(
        kind: .dragged(.primary),
        location: location,
        targetRect: scrollRoute.viewportRect,
        scrollContext: scrollContext,
        namedCoordinateSpaces: latestSemanticSnapshot.namedCoordinateSpaces,
        timestamp: timestamp
      )
    )
    return true
  }
}
