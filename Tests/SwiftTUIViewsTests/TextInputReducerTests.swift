import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Suite
struct TextInputReducerTests {
  @Test("inserts text at collapsed selection")
  func insertsTextAtCollapsedSelection() {
    let value = TextInputValue(
      text: "ac",
      selection: .caret(at: TextOffset(1))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .insertText("b"),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "abc")
    #expect(mutation.value.selection == .caret(at: TextOffset(2)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(2)))
    #expect(mutation.insertedText == "b")
    #expect(mutation.shouldWriteBinding)
    #expect(mutation.shouldRequestFrame)
  }

  @Test("replaces non-collapsed selection")
  func replacesNonCollapsedSelection() {
    let value = TextInputValue(
      text: "axc",
      selection: TextSelection(anchor: TextOffset(1), head: TextOffset(2))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .insertText("b"),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "abc")
    #expect(mutation.value.selection == .caret(at: TextOffset(2)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(2)))
  }

  @Test("backspace deletes cluster before caret")
  func backspaceDeletesClusterBeforeCaret() {
    let composed = "e\u{0301}"
    let value = TextInputValue(
      text: composed + "b",
      selection: .caret(at: TextOffset(1))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteBackward(granularity: .character),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "b")
    #expect(mutation.value.selection == .caret(at: TextOffset(0)))
    #expect(mutation.changedRange == TextRange(TextOffset(0)..<TextOffset(1)))
  }

  @Test("backspace deletes selected range")
  func backspaceDeletesSelectedRange() {
    let value = TextInputValue(
      text: "abcd",
      selection: TextSelection(anchor: TextOffset(1), head: TextOffset(3))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteBackward(granularity: .character),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "ad")
    #expect(mutation.value.selection == .caret(at: TextOffset(1)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(3)))
  }

  @Test("word backspace deletes to the previous word boundary")
  func wordBackspaceDeletesToPreviousWordBoundary() {
    let value = TextInputValue(
      text: "hello, world",
      selection: .caret(at: TextOffset(12))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteBackward(granularity: .word),
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.text == "hello, ")
    #expect(mutation.value.selection == .caret(at: TextOffset(7)))
    #expect(mutation.changedRange == TextRange(TextOffset(7)..<TextOffset(12)))
    #expect(mutation.shouldWriteBinding)
    #expect(mutation.shouldRequestFrame)
  }

  @Test("word delete deletes to the next word boundary")
  func wordDeleteDeletesToNextWordBoundary() {
    let value = TextInputValue(
      text: "hello, world",
      selection: .caret(at: TextOffset(0))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteForward(granularity: .word),
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.text == ", world")
    #expect(mutation.value.selection == .caret(at: TextOffset(0)))
    #expect(mutation.changedRange == TextRange(TextOffset(0)..<TextOffset(5)))
    #expect(mutation.shouldWriteBinding)
    #expect(mutation.shouldRequestFrame)
  }

  @Test("moves left and right by grapheme cluster")
  func movesLeftAndRightByGraphemeCluster() {
    let composed = "e\u{0301}"
    let value = TextInputValue(
      text: composed + "b",
      selection: .caret(at: TextOffset(2))
    )
    let reducer = TextInputReducer()

    let movedLeft = reducer.reduce(
      value,
      command: .move(.left, selecting: false),
      traits: .singleLine,
      layout: nil
    ).value
    let movedRight = reducer.reduce(
      movedLeft,
      command: .move(.right, selecting: false),
      traits: .singleLine,
      layout: nil
    ).value

    #expect(movedLeft.selection == .caret(at: TextOffset(1)))
    #expect(movedRight.selection == .caret(at: TextOffset(2)))
  }

  @Test("moves by word boundaries")
  func movesByWordBoundaries() {
    let value = TextInputValue(
      text: "hello, world",
      selection: .caret(at: TextOffset(12))
    )
    let reducer = TextInputReducer()

    let movedBackward = reducer.reduce(
      value,
      command: .move(.wordBackward, selecting: false),
      traits: .multiline,
      layout: nil
    ).value
    let movedForward = reducer.reduce(
      TextInputValue(text: "hello, world", selection: .caret(at: TextOffset(0))),
      command: .move(.wordForward, selecting: false),
      traits: .multiline,
      layout: nil
    ).value

    #expect(movedBackward.selection == .caret(at: TextOffset(7)))
    #expect(movedForward.selection == .caret(at: TextOffset(5)))
  }

  @Test("word movement preserves selection anchors")
  func wordMovementPreservesSelectionAnchors() {
    let value = TextInputValue(
      text: "hello, world",
      selection: .caret(at: TextOffset(12))
    )

    let moved = TextInputReducer().reduce(
      value,
      command: .move(.wordBackward, selecting: true),
      traits: .multiline,
      layout: nil
    ).value

    #expect(moved.selection == TextSelection(anchor: TextOffset(12), head: TextOffset(7)))
  }

  @Test("select all selects the full text range")
  func selectAllSelectsTheFullTextRange() {
    let value = TextInputValue(
      text: "hello\nworld",
      selection: .caret(at: TextOffset(4))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .selectAll,
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.selection == TextSelection(anchor: TextOffset(0), head: TextOffset(11)))
    #expect(!mutation.shouldWriteBinding)
    #expect(mutation.shouldRequestFrame)
  }

  @Test("copy selection reports selected text without mutating")
  func copySelectionReportsSelectedTextWithoutMutating() {
    let value = TextInputValue(
      text: "hello world",
      selection: TextSelection(anchor: TextOffset(6), head: TextOffset(11))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .copySelection,
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value == value)
    #expect(mutation.clipboardText == "world")
    #expect(!mutation.shouldWriteBinding)
    #expect(!mutation.shouldRequestFrame)
  }

  @Test("cut selection copies selected text and deletes it")
  func cutSelectionCopiesSelectedTextAndDeletesIt() {
    let value = TextInputValue(
      text: "hello world",
      selection: TextSelection(anchor: TextOffset(6), head: TextOffset(11))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .cutSelection,
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.text == "hello ")
    #expect(mutation.value.selection == .caret(at: TextOffset(6)))
    #expect(mutation.changedRange == TextRange(TextOffset(6)..<TextOffset(11)))
    #expect(mutation.clipboardText == "world")
    #expect(mutation.shouldWriteBinding)
    #expect(mutation.shouldRequestFrame)
  }

  @Test("secure copy and cut never expose clipboard text")
  func secureCopyAndCutNeverExposeClipboardText() {
    let value = TextInputValue(
      text: "secret",
      selection: TextSelection(anchor: TextOffset(0), head: TextOffset(6))
    )
    let reducer = TextInputReducer()

    let copied = reducer.reduce(
      value,
      command: .copySelection,
      traits: .secureField,
      layout: nil
    )
    let cut = reducer.reduce(
      value,
      command: .cutSelection,
      traits: .secureField,
      layout: nil
    )

    #expect(copied.value == value)
    #expect(copied.clipboardText == nil)
    #expect(!copied.shouldWriteBinding)
    #expect(cut.value == value)
    #expect(cut.clipboardText == nil)
    #expect(!cut.shouldWriteBinding)
  }

  @Test("modified key presses map to word movement, word deletion, and select all")
  func modifiedKeyPressesMapToWordMovementWordDeletionAndSelectAll() {
    #expect(
      textInputCommand(
        for: KeyPress(.arrowLeft, modifiers: .alt),
        traits: .multiline
      ) == .move(.wordBackward, selecting: false)
    )
    #expect(
      textInputCommand(
        for: KeyPress(.arrowRight, modifiers: [.shift, .alt]),
        traits: .multiline
      ) == .move(.wordForward, selecting: true)
    )
    #expect(
      textInputCommand(
        for: KeyPress(.backspace, modifiers: .alt),
        traits: .multiline
      ) == .deleteBackward(granularity: .word)
    )
    #expect(
      textInputCommand(
        for: KeyPress(.character("a"), modifiers: .ctrl),
        traits: .multiline
      ) == .selectAll
    )
    #expect(
      textInputCommand(
        for: KeyPress(.character("c"), modifiers: .ctrl),
        traits: .multiline
      ) == .copySelection
    )
    #expect(
      textInputCommand(
        for: KeyPress(.character("x"), modifiers: .ctrl),
        traits: .multiline
      ) == .cutSelection
    )
  }

  @Test("home and end move within current line")
  func homeAndEndMoveWithinCurrentLine() {
    let value = TextInputValue(
      text: "ab\ncd",
      selection: .caret(at: TextOffset(4))
    )
    let reducer = TextInputReducer()

    let movedHome = reducer.reduce(
      value,
      command: .move(.lineStart, selecting: false),
      traits: .multiline,
      layout: nil
    ).value
    let movedEnd = reducer.reduce(
      movedHome,
      command: .move(.lineEnd, selecting: false),
      traits: .multiline,
      layout: nil
    ).value

    #expect(movedHome.selection == .caret(at: TextOffset(3)))
    #expect(movedEnd.selection == .caret(at: TextOffset(5)))
  }

  @Test("up and down preserve preferred visual column")
  func upAndDownPreservePreferredVisualColumn() {
    let value = TextInputValue(
      text: "abc\nx\nabcd",
      selection: .caret(at: TextOffset(3))
    )
    let reducer = TextInputReducer()

    let movedDownToShortLine = reducer.reduce(
      value,
      command: .move(.down, selecting: false),
      traits: .multiline,
      layout: nil
    ).value
    let movedDownToLongLine = reducer.reduce(
      movedDownToShortLine,
      command: .move(.down, selecting: false),
      traits: .multiline,
      layout: nil
    ).value

    #expect(movedDownToShortLine.selection == .caret(at: TextOffset(5)))
    #expect(movedDownToShortLine.preferredVisualColumn == 3)
    #expect(movedDownToLongLine.selection == .caret(at: TextOffset(9)))
    #expect(movedDownToLongLine.preferredVisualColumn == 3)
  }

  @Test("secure traits do not change stored text")
  func secureTraitsDoNotChangeStoredText() {
    let value = TextInputValue(
      text: "pa",
      selection: .caret(at: TextOffset(2))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .insertText("ss"),
      traits: .secureField,
      layout: nil
    )

    #expect(mutation.value.text == "pass")
    #expect(mutation.value.selection == .caret(at: TextOffset(4)))
  }

  @Test("external binding update clamps selection")
  func externalBindingUpdateClampsSelection() {
    let value = TextInputValue(
      text: "abcdef",
      selection: TextSelection(anchor: TextOffset(5), head: TextOffset(6)),
      composingRange: TextRange(TextOffset(1)..<TextOffset(3)),
      preferredVisualColumn: 5
    )

    let synchronized = value.synchronized(with: "ab")

    #expect(synchronized.text == "ab")
    #expect(synchronized.selection == .caret(at: TextOffset(2)))
    #expect(synchronized.composingRange == nil)
    #expect(synchronized.preferredVisualColumn == nil)
  }

  @Test("initial external binding update places caret at end")
  func initialExternalBindingUpdatePlacesCaretAtEnd() {
    let value = TextInputValue()

    let synchronized = value.synchronized(with: "abc")

    #expect(synchronized.text == "abc")
    #expect(synchronized.selection == .caret(at: TextOffset(3)))
  }
}
