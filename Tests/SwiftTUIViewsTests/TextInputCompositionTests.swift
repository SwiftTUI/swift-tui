import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// The host/runtime editing contract at its two pure seams: the explicit
/// UTF-16 to grapheme translation, and the reducer's commit and cancel
/// policy for a marked (composing) range.
@Suite
struct TextInputCompositionTests {
  // MARK: UTF-16 translation

  @Test("UTF-16 offsets on grapheme boundaries map to Character offsets")
  func boundaryOffsets() {
    // a(1) 😀(2) e+U+0301(2) 你(1) 👩🏽‍💻(7) CR LF(2)
    let text = "a😀e\u{301}你👩🏽‍💻\r\n"
    let map = TextInputUTF16Map(text)
    #expect(map.boundaries == [0, 1, 3, 5, 6, 13, 15])
    #expect(map.utf16Count == text.utf16.count)
    for (index, unit) in map.boundaries.enumerated() {
      #expect(map.offset(utf16: unit, rounding: .down) == TextOffset(index))
      #expect(map.offset(utf16: unit, rounding: .up) == TextOffset(index))
      #expect(map.utf16Offset(for: TextOffset(index)) == unit)
    }
  }

  @Test(
    "an offset inside a grapheme snaps to that grapheme, never to a code unit",
    arguments: [
      // (UTF-16 offset, grapheme start, grapheme end)
      (2, 1, 2),  // between the surrogates of 😀
      (4, 2, 3),  // between e and its combining acute
      (7, 4, 5),  // after the first surrogate of 👩
      (10, 4, 5),  // before the zero-width joiner
      (12, 4, 5),  // between the surrogates of 💻
      (14, 5, 6),  // between CR and LF
    ])
  func insideGrapheme(unit: Int, start: Int, end: Int) {
    let map = TextInputUTF16Map("a😀e\u{301}你👩🏽‍💻\r\n")
    #expect(map.offset(utf16: unit, rounding: .down) == TextOffset(start))
    #expect(map.offset(utf16: unit, rounding: .up) == TextOffset(end))
  }

  @Test("out-of-range UTF-16 offsets have no Character offset")
  func outOfRange() {
    let map = TextInputUTF16Map("a😀")
    #expect(map.offset(utf16: -1, rounding: .up) == nil)
    #expect(map.offset(utf16: 4, rounding: .down) == nil)
    #expect(TextInputUTF16Map("").offset(utf16: 0, rounding: .up) == TextOffset(0))
    #expect(TextInputUTF16Map("").offset(utf16: 1, rounding: .up) == nil)
  }

  // MARK: Reducer policy

  @Test("a CJK candidate replaces the marked range and keeps the suffix and caret")
  func candidateReplacementMidString() {
    // "前|后" with the caret between; the user types pinyin, then picks 你好.
    var value = TextInputValue(text: "前后", selection: .caret(at: TextOffset(1)))
    value = reduce(value, editing("前ni后", caret: 3, composing: 1..<3)).value
    value = reduce(value, editing("前nihao后", caret: 6, composing: 1..<6)).value
    #expect(value.composingRange == TextRange(TextOffset(1)..<TextOffset(6)))

    let committed = reduce(value, editing("前你好后", caret: 3, composing: nil))
    #expect(committed.value.text == "前你好后")
    #expect(committed.value.selection == .caret(at: TextOffset(3)))
    #expect(committed.value.composingRange == nil)
    #expect(committed.shouldWriteBinding)
  }

  @Test("committing marked text as it stands writes nothing")
  func commitAsIsDoesNotWriteTheBinding() {
    let marked = TextInputValue(
      text: "hello", selection: .caret(at: TextOffset(5)),
      composingRange: TextRange(TextOffset(0)..<TextOffset(5)))
    for command in [TextInputCommand.finishComposition, editing("hello", caret: 5, composing: nil)]
    {
      let committed = reduce(marked, command)
      #expect(committed.value.text == "hello")
      #expect(committed.value.composingRange == nil)
      #expect(!committed.shouldWriteBinding)
      #expect(committed.shouldRequestFrame)
    }
    let again = reduce(TextInputValue(text: "hello"), .finishComposition)
    #expect(!again.shouldRequestFrame && !again.shouldWriteBinding)
  }

  @Test("cancelling a composition restores the pre-composition text and caret")
  func cancellationRestoresThePreCompositionState() {
    let before = TextInputValue(text: "ab", selection: .caret(at: TextOffset(1)))
    let composing = reduce(before, editing("anib", caret: 3, composing: 1..<3))
    #expect(composing.value.text == "anib")
    let cancelled = reduce(composing.value, editing("ab", caret: 1, composing: nil))
    #expect(cancelled.value == before)
    #expect(cancelled.shouldWriteBinding)
  }

  @Test(
    "every other command commits the composition before it applies",
    arguments: [
      TextInputCommand.insertText("x"),
      .deleteBackward(granularity: .character),
      .deleteForward(granularity: .character),
      .move(.left, selecting: false),
      .move(.lineEnd, selecting: true),
      .setSelection(.caret(at: TextOffset(0))),
      .selectAll,
      .replaceSelection("y"),
    ])
  func otherCommandsRetireTheMark(command: TextInputCommand) {
    let marked = TextInputValue(
      text: "a你好b", selection: .caret(at: TextOffset(3)),
      composingRange: TextRange(TextOffset(1)..<TextOffset(3)))
    let result = reduce(marked, command)
    #expect(result.value.composingRange == nil)
    // The marked text was committed, not removed: no command takes it away
    // except by editing it like any other text.
    if case .move = command { #expect(result.value.text == "a你好b") }
    if command == .selectAll { #expect(result.value.text == "a你好b") }
  }

  @Test("a marked range is clamped to the text and an empty one is no composition")
  func clampsTheMarkedRange() {
    let beyond = reduce(TextInputValue(), editing("ab", caret: 2, composing: 1..<9))
    #expect(beyond.value.composingRange == TextRange(TextOffset(1)..<TextOffset(2)))
    let empty = reduce(TextInputValue(), editing("ab", caret: 2, composing: 2..<2))
    #expect(empty.value.composingRange == nil)
    let stale = TextInputValue(
      text: "a", composingRange: TextRange(TextOffset(3)..<TextOffset(5))
    ).clampingSelection()
    #expect(stale.composingRange == nil)
  }

  // MARK: Presentation

  @Test("marked text is presented as composing runs only while focused")
  func presentsMarkedRuns() {
    let value = TextInputValue(
      text: "前nihao后", selection: .caret(at: TextOffset(6)),
      composingRange: TextRange(TextOffset(1)..<TextOffset(6)))
    func runs(focused: Bool) -> [TextInputDisplayRun] {
      TextInputPresentation(
        value: value, traits: .singleLine, prompt: nil, isFocused: focused,
        cursorFollowsFocus: true, width: nil
      ).displayRuns
    }
    #expect(
      runs(focused: true) == [
        .init(text: "前", isSelected: false),
        .init(text: "nihao", isSelected: false, isComposing: true),
        .init(text: "后", isSelected: false),
      ])
    #expect(runs(focused: false) == [.init(text: "前nihao后", isSelected: false)])
    // The display text is the source text: marking never adds or moves cells.
    #expect(runs(focused: true).map(\.text).joined() == value.text)
  }

  @Test("a secure field marks bullets, never the characters")
  func securePresentationStaysMasked() {
    let value = TextInputValue(
      text: "abc", selection: .caret(at: TextOffset(3)),
      composingRange: TextRange(TextOffset(1)..<TextOffset(3)))
    let presentation = TextInputPresentation(
      value: value, traits: .secureField, prompt: nil, isFocused: true,
      cursorFollowsFocus: true, width: nil)
    #expect(presentation.displayText == "•••")
    #expect(presentation.displayRuns.filter(\.isComposing).map(\.text) == ["••"])
  }

  // MARK: Support

  private func editing(_ text: String, caret: Int, composing: Range<Int>?) -> TextInputCommand {
    .setEditingState(
      text: text, selection: .caret(at: TextOffset(caret)),
      composingRange: composing.map {
        TextRange(TextOffset($0.lowerBound)..<TextOffset($0.upperBound))
      })
  }

  private func reduce(_ value: TextInputValue, _ command: TextInputCommand) -> TextInputMutation {
    TextInputReducer().reduce(value, command: command, traits: .singleLine, layout: nil)
  }
}
