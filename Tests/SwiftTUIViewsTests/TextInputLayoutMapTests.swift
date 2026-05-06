import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Suite
struct TextInputLayoutMapTests {
  @Test("caret point tracks single-line offsets")
  func caretPointTracksSingleLineOffsets() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "abc", selection: .caret(at: TextOffset(0))),
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.layoutMap.caretPoint(for: TextOffset(0)) == CellPoint(x: 0, y: 0))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(2)) == CellPoint(x: 2, y: 0))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(3)) == CellPoint(x: 3, y: 0))
  }

  @Test("nearest offset uses cell midpoints")
  func nearestOffsetUsesCellMidpoints() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "abcd", selection: .caret(at: TextOffset(0))),
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.layoutMap.nearestOffset(to: CellPoint(x: 0, y: 0)) == TextOffset(0))
    #expect(presentation.layoutMap.nearestOffset(to: CellPoint(x: 2, y: 0)) == TextOffset(2))
    #expect(presentation.layoutMap.nearestOffset(to: CellPoint(x: 20, y: 0)) == TextOffset(4))
  }

  @Test("wide grapheme occupies two cells")
  func wideGraphemeOccupiesTwoCells() {
    let wide = "\u{754C}"
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "a" + wide + "b", selection: .caret(at: TextOffset(0))),
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.layoutMap.caretPoint(for: TextOffset(1)) == CellPoint(x: 1, y: 0))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(2)) == CellPoint(x: 3, y: 0))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(3)) == CellPoint(x: 4, y: 0))
  }

  @Test("explicit newlines create new layout lines")
  func explicitNewlinesCreateNewLayoutLines() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "ab\ncd", selection: .caret(at: TextOffset(0))),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(3)) == CellPoint(x: 0, y: 1))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(5)) == CellPoint(x: 2, y: 1))
  }

  @Test("trailing newline creates empty final line")
  func trailingNewlineCreatesEmptyFinalLine() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "ab\n", selection: .caret(at: TextOffset(3))),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.lines[1].sourceRange == TextRange(TextOffset(3)..<TextOffset(3)))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(3)) == CellPoint(x: 0, y: 1))
  }

  @Test("wrapped text retains source ranges")
  func wrappedTextRetainsSourceRanges() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "abcde", selection: .caret(at: TextOffset(0))),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: 3
    )

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.lines[0].sourceRange == TextRange(TextOffset(0)..<TextOffset(3)))
    #expect(presentation.layoutMap.lines[1].sourceRange == TextRange(TextOffset(3)..<TextOffset(5)))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(4)) == CellPoint(x: 1, y: 1))
  }

  @Test("secure projection masks display but keeps source offsets")
  func secureProjectionMasksDisplayButKeepsSourceOffsets() {
    let presentation = TextInputPresentation(
      value: TextInputValue(text: "pass", selection: .caret(at: TextOffset(2))),
      traits: .secureField,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(presentation.displayText == String(repeating: "\u{2022}", count: 4) + "_")
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(2)) == CellPoint(x: 2, y: 0))
    #expect(presentation.caretAnchor == CellPoint(x: 2, y: 0))
  }

  @Test("synthetic caret is suppressed when cursor follows focus")
  func syntheticCaretIsSuppressedWhenCursorFollowsFocus() {
    let value = TextInputValue(text: "abc", selection: .caret(at: TextOffset(3)))
    let normalPresentation = TextInputPresentation(
      value: value,
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )
    let cursorPresentation = TextInputPresentation(
      value: value,
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: true,
      width: nil
    )

    #expect(normalPresentation.shouldDrawSyntheticCaret)
    #expect(normalPresentation.displayText == "abc_")
    #expect(!cursorPresentation.shouldDrawSyntheticCaret)
    #expect(cursorPresentation.displayText == "abc")
    #expect(cursorPresentation.caretAnchor == CellPoint(x: 3, y: 0))
  }
}
