import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct BrowserEditingAccessibilityTests {
  @Test(
    "browser edits preserve directed UTF-16 selection and the ordinary keyboard caret",
    arguments: [0, 1, 2], [false, true])
  func sharedSelection(kind: Int, asyncDriver: Bool) async throws {
    var text = "a😀bc"
    var writes = 0
    let binding = Binding(
      get: { text },
      set: {
        text = $0
        writes += 1
      })
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BrowserEditing"), size: .init(width: 40, height: 10)
    ) {
      Group {
        if kind == 0 {
          TextField("Editor", text: binding)
        } else if kind == 1 {
          TextEditor(text: binding).accessibilityLabel("Editor")
        } else {
          SecureField("Editor", text: binding)
        }
      }.frame(width: 30, height: 5)
    }
    defer { harness.shutdown() }
    var frames = 0
    func render() async throws {
      if asyncDriver {
        try await harness.runLoop.renderPendingFramesAsync(renderedFrames: &frames)
      } else {
        try harness.runLoop.renderPendingFrames(renderedFrames: &frames)
      }
    }
    func node() throws -> AccessibilityNode {
      try #require(
        harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
          $0.label == "Editor" && $0.control != nil
        })
    }
    func send(_ action: AccessibilityAction) throws -> AccessibilityActionResult {
      harness.runLoop.handleAccessibilityAction(
        .init(target: try #require(node().actionTarget), action: action))
    }
    #expect(try send(.focus) == .accepted)
    #expect(try send(.selectText(.init(text: text, anchor: 3, head: 1))) == .accepted)
    try await render()
    #expect(writes == 0)
    if kind == 2 {
      #expect(try node().textInput == nil)
      #expect(try node().control?.value == nil)
    } else {
      #expect(try node().textInput?.selection == 1..<3)
      #expect(try node().textInput?.insertionOffset == 1)
    }
    #expect(try send(.editText(.init(text: "a😀Xc", anchor: 4, head: 4))) == .accepted)
    try await render()
    #expect(text == "a😀Xc" && writes == 1)
    #expect(try send(.editText(.init(text: text, anchor: 4, head: 4))) == .accepted)
    #expect(writes == 1)
    _ = harness.runLoop.handle(.input(.key(.init(.character("!")))))
    try await render()
    #expect(text == "a😀X!c" && writes == 2)
    #expect(try send(.selectText(.init(text: "obsolete", anchor: 0, head: 2))) == .invalidValue)
    for offset in [-1, 2, 999] {
      #expect(try send(.editText(.init(text: "a😀bc", anchor: offset, head: 0))) == .invalidValue)
    }
    #expect(text == "a😀X!c" && writes == 2)
    if kind == 1 {
      #expect(try send(.editText(.init(text: "a\nbc\nlast", anchor: 4, head: 2))) == .accepted)
      try await render()
      #expect(try node().textInput?.selection == 2..<4)
      #expect(try node().textInput?.insertionOffset == 2)
    } else {
      #expect(try send(.editText(.init(text: "a\nb", anchor: 0, head: 0))) == .invalidValue)
    }
  }

  @Test("read-only editors permit range review without permitting text writes")
  func readOnly() throws {
    var text = "Review this"
    var writes = 0
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ReadOnlyBrowserEditing"), size: .init(width: 40, height: 8)
    ) {
      TextField(
        "Editor",
        text: Binding(
          get: { text },
          set: {
            text = $0
            writes += 1
          })
      )
      .accessibilityProperties(.init(readOnly: true))
    }
    defer { harness.shutdown() }
    let target = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.label == "Editor"
      }?.actionTarget)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .selectText(.init(text: text, anchor: 0, head: 6))))
        == .accepted)
    #expect(
      harness.runLoop.handleAccessibilityAction(
        .init(target: target, action: .editText(.init(text: "Changed", anchor: 0, head: 0))))
        == .unsupported)
    #expect(writes == 0)
  }

  @Test(
    "editor wire requests retain Unicode text, direction and correlation and reject malformed offsets"
  )
  func wire() {
    let parsed = AccessibilityActionWire.parseCommand(
      "accessibility:42:field%3A1:editText:text:a%F0%9F%98%80bc:3:1")
    #expect(
      parsed
        == .init(
          target: "field:1", action: .editText(.init(text: "a😀bc", anchor: 3, head: 1)),
          requestID: 42))
    #expect(
      AccessibilityActionWire.parseCommand("accessibility:field:selectText:text:abc:0:2")?.action
        == .selectText(.init(text: "abc", anchor: 0, head: 2)))
    for input in [
      "accessibility:1:x:editText:text:abc:-1:0", "accessibility:1:x:selectText:text:abc:0:NaN",
      "accessibility:1:x:editText:text:%FF:0:0", "accessibility:1:x:editText:text:abc:0",
      "accessibility:1:x:editText:text:abc:0:0:extra",
    ] {
      #expect(AccessibilityActionWire.parseCommand(input) == nil)
    }
  }
}
