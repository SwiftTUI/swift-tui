@_spi(Testing) import SwiftTUITestSupport
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct FocusRequestConsumptionTests {
  @Test("a satisfied request is consumed even when assigning it changes no value")
  func noOpRequestDoesNotReclaimFocus() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["NoOpFocusRequest"]), size: .init(width: 50, height: 10)
    ) { NoOpFocusRequestFixture() }
    defer { h.shutdown() }
    let field = try h.focusIdentity(forText: "First field")
    let next = try h.focusIdentity(forText: "Next control")
    #expect(h.runLoop.focusTracker.currentFocusIdentity == field)
    _ = try h.pressKey(.init(.character("f"), modifiers: .ctrl))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == field)
    _ = try h.pressKey(.init(.tab))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == next)
    _ = try h.pressKey(.init(.character("p"), modifiers: .ctrl))
    #expect(h.runLoop.focusTracker.currentFocusIdentity == next)
  }

  @Test("unmounted assistive requests are consumed before their target appears")
  func unmountedAssistiveRequestDoesNotWaitForTarget() throws {
    let h = try StressRuntimeHarness(
      rootIdentity: Identity(components: ["UnmountedReviewRequest"]),
      size: .init(width: 50, height: 10)
    ) { UnmountedReviewRequestFixture() }
    defer { h.shutdown() }
    _ = try h.clickText("Request review")
    #expect(h.frame.contains("review: false"))
    _ = try h.clickText("Reveal")
    #expect(h.frame.contains("Review target"))
    #expect(h.frame.contains("review: false"))
    #expect(
      !h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
  }
}

private struct NoOpFocusRequestFixture: View {
  @FocusState private var focused: Bool
  @State private var repaint = 0
  var body: some View {
    VStack {
      Button("First field") {}.focused($focused)
      Button("Next control") {}
      Text("Repaint: \(repaint)")
    }
    .onKeyPress(.character("f"), modifiers: .ctrl) { _ in
      focused = true
      return .handled
    }
    .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
      repaint += 1
      return .handled
    }
  }
}

private struct UnmountedReviewRequestFixture: View {
  @AccessibilityFocusState private var review: Bool
  @State private var visible = false
  var body: some View {
    VStack {
      Button("Request review") { review = true }
      Button("Reveal") { visible = true }
      Text("review: \(review)")
      if visible { Text("Review target").accessibilityFocused($review) }
    }
  }
}
