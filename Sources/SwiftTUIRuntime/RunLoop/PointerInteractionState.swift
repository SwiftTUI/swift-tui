import SwiftTUICore

/// The run loop's pointer-routing state: which interaction route, if any, owns
/// the active press, and where that press began.
///
/// These four fields move together through a small set of intent-named
/// transitions so no handler can leave a partial tuple behind. A stale
/// `armedRouteID` or `capturedRouteID` — or an `armedRouteUsesPointerHandler`
/// flag that outlives the route it described — is the exact shape of the
/// recurring drag / scroll-takeover regressions, where a missed reset on one
/// code path mis-routes the *next* gesture. Mutation is therefore restricted to
/// the transitions (`private(set)`): call sites read the fields freely but can
/// only change them coherently.
package struct PointerInteractionState: Equatable, Sendable {
  /// Route armed to *activate on release* — a tapped button, an
  /// `onTapGesture`. Unlike a captured route, an armed route can still yield to
  /// an ancestor scroll view if the press grows into a pan.
  package private(set) var armedRouteID: RouteID?

  /// Whether the armed route is driven by a custom pointer handler (a gesture
  /// that wants the full pressed stream) rather than a plain activation action.
  package private(set) var armedRouteUsesPointerHandler = false

  /// Route that has *captured* the pointer stream for the gesture's whole
  /// lifetime — a slider drag, a scroll pan. A captured route never yields.
  package private(set) var capturedRouteID: RouteID?

  /// Where the active press began, retained while a route is armed or captured
  /// so a drag that crosses the scroll-takeover threshold can be measured from
  /// the press origin. Set on `.down`, cleared on `.up`.
  package private(set) var dragStartLocation: PointerLocation?

  package init() {}

  /// True while any route owns the press (armed or captured) — gates whether a
  /// bare pointer-move still needs a frame.
  package var isRouting: Bool {
    armedRouteID != nil || capturedRouteID != nil
  }

  /// Record where a fresh press began. The routing decision (``arm(_:usesPointerHandler:)``
  /// or ``capture(_:)``) follows once the hit target is classified.
  package mutating func beginPress(at location: PointerLocation) {
    dragStartLocation = location
  }

  /// Arm a non-capturing route to activate on release. Clears any capture so the
  /// armed and captured routes are never both live.
  package mutating func arm(_ routeID: RouteID, usesPointerHandler: Bool) {
    armedRouteID = routeID
    armedRouteUsesPointerHandler = usesPointerHandler
    capturedRouteID = nil
  }

  /// Capture the pointer stream on a route for the gesture's whole lifetime,
  /// clearing any armed route — e.g. a drag handed off from an inner control to
  /// an ancestor scroll view. The press origin is retained so the captured pan
  /// can keep measuring from where the press began.
  package mutating func capture(_ routeID: RouteID) {
    capturedRouteID = routeID
    armedRouteID = nil
    armedRouteUsesPointerHandler = false
  }

  /// Re-key the armed route after a mid-press re-mint: the control's region
  /// re-appeared under the same identity + kind with a fresh `ownerNodeID`, so
  /// subsequent events must pair against the fresh route. The pointer-handler
  /// flag and press origin describe the logical interaction, not the node, and
  /// carry over unchanged. No-op unless a route is armed.
  package mutating func rekeyArmedRoute(to routeID: RouteID) {
    guard armedRouteID != nil else {
      return
    }
    armedRouteID = routeID
  }

  /// Captured counterpart of ``rekeyArmedRoute(to:)``: keeps a mid-gesture
  /// capture pointing at the control's live route across a re-mint instead of
  /// letting the stale route force-release the capture.
  package mutating func rekeyCapturedRoute(to routeID: RouteID) {
    guard capturedRouteID != nil else {
      return
    }
    capturedRouteID = routeID
  }

  /// Drop all routing — armed and captured — but keep the press origin. Used
  /// when a press resolves to nothing actionable, or when a captured region
  /// disappears from the rendered tree mid-interaction.
  package mutating func clearRouting() {
    armedRouteID = nil
    armedRouteUsesPointerHandler = false
    capturedRouteID = nil
  }

  /// Full teardown to the idle state, including the press origin. Used on `.up`
  /// and when a press lands outside any interaction region.
  package mutating func reset() {
    armedRouteID = nil
    armedRouteUsesPointerHandler = false
    capturedRouteID = nil
    dragStartLocation = nil
  }
}
