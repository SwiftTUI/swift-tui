import SwiftTUICore
import Testing

@Suite
struct AccessibilityTextInputLayoutTests {
  @Test(arguments: ["\u{85}", "\u{2028}", "\u{2029}", "\u{B}", "\u{C}"])
  func nonBreakingControlAtEndKeepsCursorOnRenderedLine(_ suffix: String) {
    let text = "ABC" + suffix
    #expect(
      wrappedTextCursorAnchor(text, offset: text.count, width: 20)
        == CellPoint(x: 3 + cellWidth(of: suffix.first!), y: 0))
  }

  @Test
  func newlineClusterFollowsSyntheticCaret() {
    let input = accessibilityTextInput(
      .init(text: "AB\nCD", anchor: 2, head: 2, displayText: "AB_\nCD"),
      bounds: .init(origin: .zero, size: .init(width: 20, height: 3)), wraps: true)
    #expect(input.clusters[2].rect.origin == CellPoint(x: 3, y: 0))
    #expect(input.clusters[3].rect.origin == CellPoint(x: 0, y: 1))
    #expect(input.endAnchor == CellPoint(x: 2, y: 1))
  }

  @Test
  func unicodeSelectionUsesUTF16AndPlacedGeometry() {
    let input = accessibilityTextInput(
      .init(text: "A😀e\u{301}\nZ", anchor: 3, head: 1),
      bounds: .init(origin: .init(x: 7, y: 9), size: .init(width: 20, height: 3)),
      wraps: true)
    #expect(input.selection == 1..<5)
    #expect(input.insertionOffset == 1)
    #expect(input.clusters.map(\.range) == [0..<1, 1..<3, 3..<5, 5..<6, 6..<7])
    #expect(input.clusters[1].rect.origin == CellPoint(x: 8, y: 9))
    #expect(input.clusters[1].rect.size.width == 2)
    #expect(input.clusters[4].rect.origin == CellPoint(x: 7, y: 10))
    #expect(input.endAnchor == CellPoint(x: 8, y: 10))
  }

  @Test
  func emptyLogicalLinesRetainDistinctCaretRows() {
    #expect(
      wrappedTextCursorAnchors("ab\n\ncd\n", width: 10) == [
        .init(x: 0, y: 0), .init(x: 1, y: 0), .init(x: 2, y: 0),
        .init(x: 0, y: 1), .init(x: 0, y: 2), .init(x: 1, y: 2),
        .init(x: 2, y: 2), .init(x: 0, y: 3),
      ])
  }
}
