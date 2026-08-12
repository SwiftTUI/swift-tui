import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

@Suite
struct PointerInteractionStateTests {
  private func route(_ name: String) -> RouteID {
    RouteID(identity: testIdentity(name))
  }

  private func location(_ x: Int, _ y: Int) -> PointerLocation {
    .cellFallback(CellPoint(x: x, y: y))
  }

  @Test("a fresh state is fully idle")
  func freshStateIsIdle() {
    let state = PointerInteractionState()
    #expect(state.armedRouteID == nil)
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.capturedRouteID == nil)
    #expect(state.dragStartLocation == nil)
    #expect(state.deadlineDispatchOutcome == nil)
    #expect(state.pointerHandlerIdentity == nil)
    #expect(state.activeRouteID == nil)
    #expect(state.isRouting == false)
  }

  @Test("beginPress records the origin without arming or capturing")
  func beginPressRecordsOriginOnly() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4), focusedValues: FocusedValues())
    #expect(state.dragStartLocation == location(3, 4))
    #expect(state.armedRouteID == nil)
    #expect(state.capturedRouteID == nil)
    #expect(state.isRouting == false)
  }

  @Test("arm sets the armed route and the handler flag, keeping the origin")
  func armSetsRouteAndFlag() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4), focusedValues: FocusedValues())
    state.arm(route("Button"), usesPointerHandler: true)
    #expect(state.armedRouteID == route("Button"))
    #expect(state.armedRouteUsesPointerHandler == true)
    #expect(state.capturedRouteID == nil)
    #expect(state.dragStartLocation == location(3, 4))
    #expect(state.pointerHandlerIdentity == route("Button").identity)
    #expect(state.isRouting == true)
  }

  @Test("capture sets the captured route and clears the armed route + flag")
  func captureClearsArmedAndFlag() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4), focusedValues: FocusedValues())
    state.arm(route("Button"), usesPointerHandler: true)
    state.capture(route("Scroll"))
    #expect(state.capturedRouteID == route("Scroll"))
    #expect(state.armedRouteID == nil)
    // The handler flag must not outlive the armed route it described — leaving
    // it set is the classic drift that mis-routes the next gesture.
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.dragStartLocation == location(3, 4))
    #expect(state.pointerHandlerIdentity == route("Scroll").identity)
    #expect(state.isRouting == true)
  }

  @Test("arm after capture clears the captured route (mutual exclusion)")
  func armAfterCaptureClearsCaptured() {
    var state = PointerInteractionState()
    state.capture(route("Scroll"))
    state.arm(route("Button"), usesPointerHandler: false)
    #expect(state.armedRouteID == route("Button"))
    #expect(state.capturedRouteID == nil)
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.pointerHandlerIdentity == nil)
  }

  @Test("clearRouting drops both routes and the flag but keeps the origin")
  func clearRoutingKeepsOrigin() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8), focusedValues: FocusedValues())
    state.arm(route("Button"), usesPointerHandler: true)
    state.clearRouting()
    #expect(state.armedRouteID == nil)
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.capturedRouteID == nil)
    #expect(state.dragStartLocation == location(7, 8))
    #expect(state.pointerHandlerIdentity == nil)
    #expect(state.isRouting == false)
  }

  @Test("fallback pointer-handler identity is independent of the armed hit route")
  func fallbackHandlerIdentityIsIndependentOfArmedRoute() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8), focusedValues: FocusedValues())
    state.arm(
      route("Button"),
      usesPointerHandler: true,
      pointerHandlerIdentity: route("AncestorGesture").identity
    )

    #expect(state.armedRouteID == route("Button"))
    #expect(state.pointerHandlerIdentity == route("AncestorGesture").identity)
  }

  @Test("clearRouting releases a captured route too")
  func clearRoutingReleasesCapture() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8), focusedValues: FocusedValues())
    state.capture(route("Scroll"))
    state.clearRouting()
    #expect(state.capturedRouteID == nil)
    #expect(state.armedRouteID == nil)
    #expect(state.dragStartLocation == location(7, 8))
    #expect(state.isRouting == false)
  }

  @Test("reset returns to the fully idle state including the origin")
  func resetClearsEverything() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8), focusedValues: FocusedValues())
    state.capture(route("Scroll"))
    state.reset()
    #expect(state == PointerInteractionState())
    #expect(state.dragStartLocation == nil)
    #expect(state.isRouting == false)
  }

  @Test("deadline recognition stays role-aware until release and reset")
  func deadlineRecognitionStaysRoleAwareUntilReset() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8), focusedValues: FocusedValues())
    state.arm(route("Button"), usesPointerHandler: true)
    #expect(state.activeRouteID == route("Button"))

    state.noteDeadlineDispatchOutcome(.observed)
    #expect(state.deadlineDispatchOutcome == .observed)
    #expect(state.releaseOutcome(combining: .ignored) == .observed)

    state.noteDeadlineDispatchOutcome(.failed)
    #expect(state.deadlineDispatchOutcome == .observed)

    state.noteDeadlineDispatchOutcome(.claimed)
    #expect(state.deadlineDispatchOutcome == .claimed)
    #expect(state.releaseOutcome(combining: .observed) == .claimed)

    state.reset()
    #expect(state.deadlineDispatchOutcome == nil)
    #expect(state.releaseOutcome(combining: .failed) == .failed)
  }
}
