import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite
struct TextFieldViewportTests {
  @Test("the editing viewport follows both caret directions without disturbing siblings")
  func viewportFollowsCaret() throws {
    let identity = testIdentity("ViewportField")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ViewportRoot"), size: .init(width: 12, height: 1)
    ) {
      HStack(spacing: 0) {
        TextField("Value", text: .constant("abcdefghij"))
          .id(identity).textFieldStyle(.plain).frame(width: 5, alignment: .leading)
        Text("|")
      }
    }
    defer { harness.shutdown() }
    _ = try harness.focus(identity)
    #expect(harness.frame.contains("ghij_|"), "\(harness.frame)")
    _ = try harness.pressKey(.init(.home))
    #expect(harness.frame.contains("abcde|"), "\(harness.frame)")
    _ = try harness.pressKey(.init(.end))
    #expect(harness.frame.contains("ghij_|"), "\(harness.frame)")
    let node = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .textField
      })
    #expect(node.cursorAnchor?.x == 4)
  }

  @Test("a native caret gets a visible cell without scrolling text that fits")
  func nativeCaretReservesItsCell() throws {
    let identity = testIdentity("NativeViewportField")
    var environment = EnvironmentValues()
    environment.focusedIdentity = identity
    environment.cursorFollowsFocus = true
    let renderer = DefaultRenderer()
    defer { withExtendedLifetime(renderer) {} }
    let snapshot = renderer.render(
      TextField("Value", text: .constant("abc")).id(identity).textFieldStyle(.plain),
      context: .init(
        identity: testIdentity("Root"), environmentValues: environment,
        applyEnvironmentValues: true), proposal: .init(width: 4, height: 1))
    #expect(snapshot.rasterSurface.lines == ["abc"])
    let node = try #require(
      snapshot.semanticSnapshot.accessibilityNodes.first { $0.role == .textField })
    #expect(node.cursorAnchor?.x == 3)
    #expect(snapshot.measuredTree.measuredSize.width == 4)
  }
}
