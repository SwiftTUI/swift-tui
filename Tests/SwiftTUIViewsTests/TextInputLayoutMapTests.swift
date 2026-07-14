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

  @Test("width-limited map rows match the rendered word-boundary wrap")
  func widthLimitedMapMatchesRenderedWrap() {
    let text = "alpha beta gamma"
    let presentation = TextInputPresentation(
      value: TextInputValue(text: text, selection: .caret(at: TextOffset(0))),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: 7
    )
    let map = presentation.layoutMap

    // The renderer wraps at word boundaries; the movement map must produce
    // the same rows or Up/Down and click-to-caret target rows the renderer
    // never drew (F140).
    let rendered = layoutText(for: text, width: 7).lines.map(\.text)
    #expect(rendered == ["alpha", "beta", "gamma"])
    let mapRows = map.lines.map { line in String(line.clusters.map(\.display)) }
    #expect(mapRows == rendered)

    // "alpha beta gamma": 'b' of "beta" is offset 6 and renders at row 1
    // column 0; 'g' of "gamma" is offset 11 at row 2 column 0.
    let bOffset = TextOffset(6)
    #expect(map.caretPoint(for: bOffset) == CellPoint(x: 0, y: 1))
    let down = map.verticalOffset(from: bOffset, delta: 1, preferredVisualColumn: nil)
    #expect(down.offset == TextOffset(11))
    let up = map.verticalOffset(from: bOffset, delta: -1, preferredVisualColumn: nil)
    #expect(up.offset == TextOffset(0))
    #expect(map.nearestOffset(to: CellPoint(x: 0, y: 2)) == TextOffset(11))

    // The separator space swallowed at the wrap point belongs to the row it
    // followed: the caret there renders at that row's end, like the renderer
    // (which draws nothing for it).
    #expect(map.caretPoint(for: TextOffset(5)) == CellPoint(x: 5, y: 0))
  }

  @Test("continuation-marker rows keep caret columns aligned with rendered cells")
  func continuationMarkerRowsAlignCaretColumns() {
    let text = "abcdef"
    let presentation = TextInputPresentation(
      value: TextInputValue(text: text, selection: .caret(at: TextOffset(0))),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: 3
    )
    let map = presentation.layoutMap

    // An over-wide word splits with continuation markers; the rendered rows
    // are "ab–" / "–c–" / "–d–" / "–ef".
    #expect(layoutText(for: text, width: 3).lines.map(\.text) == ["ab–", "–c–", "–d–", "–ef"])
    #expect(map.lines.map { String($0.clusters.map(\.display)) } == ["ab", "c", "d", "ef"])

    // Markers occupy cells but own no source offsets: content on a
    // continuation row starts at column 1, after the leading marker, and a
    // caret INSIDE a row's content renders at marker-adjusted columns.
    // Boundary offsets keep the map's end-of-row affinity (the newline-gap
    // policy): the caret between 'b' and 'c' renders at the end of row 0.
    #expect(map.caretPoint(for: TextOffset(2)) == CellPoint(x: 2, y: 0))
    #expect(map.caretPoint(for: TextOffset(3)) == CellPoint(x: 2, y: 1))
    #expect(map.caretPoint(for: TextOffset(5)) == CellPoint(x: 2, y: 3))
    #expect(map.caretPoint(for: TextOffset(6)) == CellPoint(x: 3, y: 3))
    // Clicking the leading marker cell resolves to the row's first source
    // offset.
    #expect(map.nearestOffset(to: CellPoint(x: 0, y: 1)) == TextOffset(2))
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

    // An unbroken over-wide word splits mid-word with continuation markers,
    // exactly as the renderer draws it: "ab–" / "–c–" / "–de".
    #expect(presentation.layoutMap.lines.count == 3)
    #expect(presentation.layoutMap.lines[0].sourceRange == TextRange(TextOffset(0)..<TextOffset(2)))
    #expect(presentation.layoutMap.lines[1].sourceRange == TextRange(TextOffset(2)..<TextOffset(3)))
    #expect(presentation.layoutMap.lines[2].sourceRange == TextRange(TextOffset(3)..<TextOffset(5)))
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(4)) == CellPoint(x: 2, y: 2))
  }

  @Test("selection rects span explicit and wrapped lines")
  func selectionRectsSpanExplicitAndWrappedLines() {
    let multilinePresentation = TextInputPresentation(
      value: TextInputValue(
        text: "ab\ncd",
        selection: TextSelection(anchor: TextOffset(1), head: TextOffset(4))
      ),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )
    let wrappedPresentation = TextInputPresentation(
      value: TextInputValue(
        text: "abcdef",
        selection: TextSelection(anchor: TextOffset(2), head: TextOffset(5))
      ),
      traits: .multiline,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: 3
    )

    #expect(
      multilinePresentation.selectionRects
        == [
          CellRect(origin: CellPoint(x: 1, y: 0), size: CellSize(width: 1, height: 1)),
          CellRect(origin: CellPoint(x: 0, y: 1), size: CellSize(width: 1, height: 1)),
        ]
    )
    // "abcdef" at width 3 renders "ab–" / "–c–" / "–d–" / "–ef"; the
    // selection [2, 5) covers 'c', 'd', and 'e' at their marker-adjusted
    // columns.
    #expect(
      wrappedPresentation.selectionRects
        == [
          CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 1, height: 1)),
          CellRect(origin: CellPoint(x: 1, y: 2), size: CellSize(width: 1, height: 1)),
          CellRect(origin: CellPoint(x: 1, y: 3), size: CellSize(width: 1, height: 1)),
        ]
    )
  }

  @Test("focused range selection suppresses synthetic caret")
  func focusedRangeSelectionSuppressesSyntheticCaret() {
    let presentation = TextInputPresentation(
      value: TextInputValue(
        text: "hello",
        selection: TextSelection(anchor: TextOffset(1), head: TextOffset(4))
      ),
      traits: .singleLine,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(!presentation.shouldDrawSyntheticCaret)
    #expect(presentation.displayText == "hello")
    #expect(presentation.displayRuns.map(\.text).joined() == "hello")
    #expect(presentation.displayRuns.map(\.isSelected) == [false, true, false])
  }

  @Test("selection rendering is focused-only and keeps secure text redacted")
  func selectionRenderingIsFocusedOnlyAndKeepsSecureTextRedacted() {
    let secureSelection = TextSelection(anchor: TextOffset(1), head: TextOffset(4))
    let securePresentation = TextInputPresentation(
      value: TextInputValue(text: "secret", selection: secureSelection),
      traits: .secureField,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: false,
      width: nil
    )
    let unfocusedPresentation = TextInputPresentation(
      value: TextInputValue(
        text: "visible", selection: TextSelection(anchor: TextOffset(1), head: TextOffset(4))),
      traits: .singleLine,
      prompt: nil,
      isFocused: false,
      cursorFollowsFocus: false,
      width: nil
    )

    #expect(
      securePresentation.displayRuns.map(\.text).joined() == String(repeating: "\u{2022}", count: 6)
    )
    #expect(securePresentation.displayRuns.map(\.isSelected) == [false, true, false])
    #expect(!securePresentation.displayText.contains("secret"))
    #expect(unfocusedPresentation.displayRuns.map(\.isSelected) == [false])
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
