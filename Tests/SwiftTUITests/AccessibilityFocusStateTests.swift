import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AccessibilityFocusStateTests {
  @Test(
    "assistive focus is independent, generation-scoped and lifetime-guarded",
    arguments: [false, true])
  func independentFocus(asyncDriver: Bool) async throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AssistiveFocus"),
      size: .init(width: 80, height: 20)
    ) { AssistiveFocusFixture() }
    defer { harness.shutdown() }
    var frames = 0
    func render() async throws {
      if asyncDriver {
        try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
      } else {
        try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
      }
    }
    func node(_ label: String) throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == label
        })
    }
    func send(_ label: String, _ action: AccessibilityAction = .activate) async throws {
      let target = try #require(node(label).actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      try await render()
    }
    let keyboard = harness.runLoop.focusTracker.currentFocusIdentity
    #expect(keyboard != nil)
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
    let heading = try node("Review heading")
    #expect(heading.control?.actions.contains(.focus) == false)
    #expect(
      !harness.runLoop.focusTracker.focusRegions.contains { $0.identity == heading.actionIdentity })

    try await send("Review heading", .accessibilityFocus)
    #expect(try node("Review heading").isAccessibilityFocused)
    #expect(try node("Review heading; keyboard true").role == .group)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboard)
    #expect(harness.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest == nil)

    try await send("Request disabled")
    #expect(try node("Unavailable").isAccessibilityFocused)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboard)
    let generation = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest?.generation)
    try await send("Repaint")
    #expect(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest?.generation
        == generation)
    // A late blur from the old node cannot clear the newer semantic focus.
    try await send("Review heading", .accessibilityBlur)
    #expect(try node("Unavailable").isAccessibilityFocused)
    try await send("Unavailable", .accessibilityBlur)
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })

    try await send("Request heading")
    let oldTarget = try #require(node("Review heading").actionTarget)
    try await send("Toggle review content")
    #expect(try node("Review none; keyboard true").role == .group)
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
    try await send("Toggle review content")
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: oldTarget, action: .accessibilityFocus)) == .staleTarget)
    try await send("Request heading")
    #expect(try node("Review heading").isAccessibilityFocused)
    try await send("Clear review")
    #expect(harness.runLoop.publishedAccessibilitySnapshot.accessibilityFocusRequest?.target == nil)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboard)
  }
}

private struct AssistiveFocusFixture: View {
  @State private var text = ""
  @State private var visible = true
  @State private var counter = 0
  @FocusState private var keyboard: Bool
  @AccessibilityFocusState private var review: String?

  var body: some View {
    VStack(alignment: .leading) {
      TextField("Editor", text: $text).focused($keyboard)
      Text("Review \(review ?? "none"); keyboard \(keyboard)")
      if visible {
        Text("Review heading").accessibilityProperties(.init(headingLevel: 2))
          .accessibilityFocused($review, equals: "heading")
        Button("Unavailable") {}.disabled(true).accessibilityFocused($review, equals: "disabled")
      }
      Button("Request heading") { review = "heading" }
      Button("Request disabled") { review = "disabled" }
      Button("Clear review") { review = nil }
      Button("Toggle review content") { visible.toggle() }
      Button("Repaint") { counter += 1 }
      Text("Count \(counter)")
    }
  }
}

extension AccessibilityFocusStateTests {
  @Test("boolean review bindings respect modal scope and named navigation stays independent")
  func modalScope() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("AssistiveModal"),
      size: .init(width: 60, height: 20)
    ) { AssistiveModalFixture() }
    defer { harness.shutdown() }
    var frames = 0
    func node(_ name: String) throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first { $0.label == name }
      )
    }
    func dispatch(_ name: String, _ action: AccessibilityAction) throws {
      let target = try #require(node(name).actionTarget)
      #expect(
        harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
          == .accepted)
      try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
    }
    let background = try node("Background heading")
    #expect(background.navigationCategories == ["Chapters"])
    #expect(background.control?.actions.contains(.focus) == false)
    let oldTarget = try #require(background.actionTarget)
    try dispatch("Background heading", .accessibilityFocus)
    #expect(try node("Background heading").isAccessibilityFocused)
    try dispatch("Show dialog", .activate)
    let result = harness.runLoop.handleAccessibilityAction(
      .init(target: oldTarget, action: .accessibilityFocus))
    #expect(result == .outOfScope || result == .staleTarget)
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Background heading" && $0.isAccessibilityFocused
      })
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Background heading" || $0.label == "Show dialog"
      })
    let keyboard = harness.runLoop.focusTracker.currentFocusIdentity
    try dispatch("Dialog heading", .accessibilityFocus)
    #expect(try node("Dialog heading").isAccessibilityFocused)
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == keyboard)
    try dispatch("Close dialog", .activate)
    #expect(
      !harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.isAccessibilityFocused
      })
    #expect(try node("Review background false; dialog false").role == .group)
  }
}

private struct AssistiveModalFixture: View {
  @State private var modal = false
  @AccessibilityFocusState private var background: Bool
  @AccessibilityFocusState private var dialog: Bool
  var body: some View {
    VStack {
      Text("Background heading").accessibilityNavigationCategory("Chapters")
        .accessibilityNavigationCategory("Chapters").accessibilityFocused($background)
      Text("Review background \(background); dialog \(dialog)")
      Button("Show dialog") { modal = true }
    }.sheet(isPresented: $modal) {
      VStack {
        Text("Dialog heading").accessibilityFocused($dialog)
        Button("Close dialog") { modal = false }
      }
    }
  }
}
