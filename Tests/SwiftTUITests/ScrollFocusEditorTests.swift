import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct ScrollFocusEditorTests {
  @Test
  func movingTheCaretDoesNotRecoverTheOuterViewport() throws {
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("NestedEditorFocus"), size: CellSize(width: 48, height: 12)
    ) { NestedEditorFocusFixture() }
    defer { harness.shutdown() }
    _ = try harness.focus(NestedEditorFocusFixture.editorIdentity)
    try #require(harness.frame.contains("Editor 11"))
    let initialInnerRoute = try #require(
      harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
        harness.runLoop.latestSemanticSnapshot.scrollRoutes
      ).first { $0.identity.isDescendant(of: NestedEditorFocusFixture.editorIdentity) })
    try #require(initialInnerRoute.contentOffset.y > 0)

    _ = try harness.pressKey(KeyPress(.character("m"), modifiers: .ctrl))
    try #require(harness.frame.contains("Outer offset: 12"))
    try #require(!harness.frame.contains("Editor 11"))
    for _ in 0..<11 {
      _ = try harness.pressKey(KeyPress(.arrowUp))
      #expect(harness.frame.contains("Outer offset: 12"), "\(harness.frame)")
      #expect(
        harness.runLoop.focusTracker.currentFocusIdentity == NestedEditorFocusFixture.editorIdentity
      )
    }
    let finalInnerRoute = try #require(
      harness.runLoop.localScrollPositionRegistry.routesWithCurrentOffsets(
        harness.runLoop.latestSemanticSnapshot.scrollRoutes
      ).first { $0.identity == initialInnerRoute.identity })
    #expect(finalInnerRoute.contentOffset.y == 0)
  }
}

private struct NestedEditorFocusFixture: View {
  static let editorIdentity = testIdentity("NestedEditorFocus", "Editor")
  @State private var position = ScrollCellOffset.zero
  @State private var text = (0..<12).map { "Editor \($0)" }.joined(separator: "\n")

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ScrollView(.vertical, position: $position) {
        VStack(alignment: .leading, spacing: 0) {
          TextEditor(text: $text)
            .id(Self.editorIdentity)
            .frame(width: 28, height: 5)
          ForEach(0..<24, id: \.self) { row in Text("Tail \(row)") }
        }
      }
      .scrollIndicators(.hidden)
      .frame(width: 32, height: 6, alignment: .topLeading)
      Text("Outer offset: \(position.y)")
    }
    .onKeyPress(.character("m"), modifiers: .ctrl) { _ in
      position = ScrollCellOffset(x: 0, y: 12)
      return .handled
    }
  }
}
