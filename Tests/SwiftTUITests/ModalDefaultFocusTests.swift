import Testing

@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct ModalDefaultFocusTests {
  @Test("Explicitly clearing focus survives subsequent frames of the same modal")
  func clearedModalFocus() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ModalDefaultFocus"), size: .init(width: 40, height: 15)
    ) { ModalFocusFixture() }
    defer { harness.shutdown() }
    let candidate = try #require(harness.runLoop.focusTracker.currentFocusIdentity)
    _ = try harness.pressKey(.init(.character("c")))
    for _ in 0..<2 {
      _ = try harness.renderAfterExternalMutation()
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == nil)
    }
    _ = try harness.focusText("Candidate")
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == candidate)
  }
}

private struct ModalFocusFixture: View {
  @Namespace private var namespace
  @FocusState private var focused: Bool
  @State private var presented = true

  var body: some View {
    Text("base").sheet(isPresented: $presented) {
      VStack {
        Button("Candidate") {}.focused($focused).prefersDefaultFocus(true, in: namespace)
        Button("Other") {}
      }
      .focusScope(namespace)
      .onKeyPress(.character("c")) { _ in
        focused = false
        return .handled
      }
    }
  }
}
