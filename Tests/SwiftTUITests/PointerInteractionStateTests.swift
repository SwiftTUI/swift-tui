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
    #expect(state.isRouting == false)
  }

  @Test("beginPress records the origin without arming or capturing")
  func beginPressRecordsOriginOnly() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4))
    #expect(state.dragStartLocation == location(3, 4))
    #expect(state.armedRouteID == nil)
    #expect(state.capturedRouteID == nil)
    #expect(state.isRouting == false)
  }

  @Test("arm sets the armed route and the handler flag, keeping the origin")
  func armSetsRouteAndFlag() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4))
    state.arm(route("Button"), usesPointerHandler: true)
    #expect(state.armedRouteID == route("Button"))
    #expect(state.armedRouteUsesPointerHandler == true)
    #expect(state.capturedRouteID == nil)
    #expect(state.dragStartLocation == location(3, 4))
    #expect(state.isRouting == true)
  }

  @Test("capture sets the captured route and clears the armed route + flag")
  func captureClearsArmedAndFlag() {
    var state = PointerInteractionState()
    state.beginPress(at: location(3, 4))
    state.arm(route("Button"), usesPointerHandler: true)
    state.capture(route("Scroll"))
    #expect(state.capturedRouteID == route("Scroll"))
    #expect(state.armedRouteID == nil)
    // The handler flag must not outlive the armed route it described — leaving
    // it set is the classic drift that mis-routes the next gesture.
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.dragStartLocation == location(3, 4))
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
  }

  @Test("clearRouting drops both routes and the flag but keeps the origin")
  func clearRoutingKeepsOrigin() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8))
    state.arm(route("Button"), usesPointerHandler: true)
    state.clearRouting()
    #expect(state.armedRouteID == nil)
    #expect(state.armedRouteUsesPointerHandler == false)
    #expect(state.capturedRouteID == nil)
    #expect(state.dragStartLocation == location(7, 8))
    #expect(state.isRouting == false)
  }

  @Test("clearRouting releases a captured route too")
  func clearRoutingReleasesCapture() {
    var state = PointerInteractionState()
    state.beginPress(at: location(7, 8))
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
    state.beginPress(at: location(7, 8))
    state.capture(route("Scroll"))
    state.reset()
    #expect(state == PointerInteractionState())
    #expect(state.dragStartLocation == nil)
    #expect(state.isRouting == false)
  }
}
