import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

// STUI-607, STUI-699 and STUI-707 motivate testing edit seams, not just
// isolated multi-scalar characters. Grapheme counts are not additive at a seam.
@Suite("Monthly adversarial editing")
struct MonthlyAdversarialEditingTests {
  @Test func audit021CombiningMarkInsertionKeepsCaretInsideText() {
    insertion("e", at: 1, insert: "\u{301}", expected: "e\u{301}", caret: 1)
  }

  @Test func audit022VariationSelectorInsertionDoesNotSkipSuffix() {
    insertion("❤x", at: 1, insert: "\u{FE0F}", expected: "❤️x", caret: 1)
  }

  @Test func audit023SkinToneInsertionDoesNotSkipSuffix() {
    insertion("👍x", at: 1, insert: "🏽", expected: "👍🏽x", caret: 1)
  }

  @Test func audit024RegionalIndicatorsMergeAcrossInsertion() {
    insertion("🇺x", at: 1, insert: "🇳", expected: "🇺🇳x", caret: 1)
  }

  @Test func audit025ZWJInsertionJoinsBothNeighbors() {
    insertion("👩💻x", at: 1, insert: "\u{200D}", expected: "👩‍💻x", caret: 1)
  }

  @Test func audit026CombiningReplacementPreservesFollowingCharacter() {
    let value = TextInputValue(text: "eQx", selection: selection(2, 1))
    let result = reduce(value, .replaceSelection("\u{301}"))
    #expect(result.value.text == "éx")
    #expect(result.value.selection == .caret(at: TextOffset(1)))
    #expect(reduce(result.value, .deleteForward(granularity: .character)).value.text == "é")
  }

  @Test func audit027CRInsertionBeforeLFProducesOneBreak() {
    insertion("\nx", at: 0, insert: "\r", expected: "\r\nx", caret: 1)
  }

  @Test func audit028HangulJamoInsertionMergesSyllable() {
    insertion("\u{1100}x", at: 1, insert: "\u{1161}", expected: "\u{1100}\u{1161}x", caret: 1)
  }

  @Test func audit029DeletionJoinsRegionalIndicatorsBeforeSuffix() {
    let value = TextInputValue(text: "🇺-🇳x", selection: .caret(at: TextOffset(2)))
    let result = reduce(value, .deleteBackward(granularity: .character))
    #expect(result.value.text == "🇺🇳x")
    #expect(result.value.selection == .caret(at: TextOffset(1)))
    #expect(reduce(result.value, .deleteForward(granularity: .character)).value.text == "🇺🇳")
  }

  @Test func audit030CutJoinsCRLFWithoutLeakingDeletedText() {
    let value = TextInputValue(text: "\rX\ny", selection: selection(2, 1))
    let result = reduce(value, .cutSelection)
    #expect(result.clipboardText == "X")
    #expect(result.value.text == "\r\ny")
    #expect(result.value.selection == .caret(at: TextOffset(1)))
  }

  @Test func audit031ExtremeReversedSelectionDeletesOnlyExistingText() {
    let value = TextInputValue(text: "a👩🏽‍💻z", selection: selection(Int.max, Int.min))
    let result = reduce(value, .deleteBackward(granularity: .word))
    #expect(result.value.text.isEmpty)
    #expect(result.value.selection == .caret(at: TextOffset(0)))
    #expect(result.shouldWriteBinding)
  }

  @Test func audit032ExtremeCaretIsClampedBeforeInsertionArithmetic() {
    let value = TextInputValue(text: "界", selection: .caret(at: TextOffset(Int.max)))
    let result = reduce(value, .insertText("!"))
    #expect(result.value.text == "界!")
    #expect(result.value.selection == .caret(at: TextOffset(2)))
  }

  @Test func audit033ShiftLeftContractsForwardSelectionAtHead() {
    let value = TextInputValue(text: "a👩🏽‍💻bcd", selection: selection(1, 4))
    let result = reduce(value, .move(.left, selecting: true))
    #expect(result.value.selection == selection(1, 3))
    #expect(!result.shouldWriteBinding)
  }

  @Test func audit034ShiftRightContractsBackwardSelectionAtHead() {
    let value = TextInputValue(text: "a👩🏽‍💻bcd", selection: selection(4, 1))
    let result = reduce(value, .move(.right, selecting: true))
    #expect(result.value.selection == selection(4, 2))
    #expect(!result.shouldWriteBinding)
  }

  @Test func audit035BackwardLineDeletionAtCRLFStartJoinsLines() {
    let value = TextInputValue(text: "界\r\n👩🏽‍💻z", selection: .caret(at: TextOffset(2)))
    let result = reduce(value, .deleteBackward(granularity: .line))
    #expect(result.value.text == "界👩🏽‍💻z")
    #expect(result.value.selection == .caret(at: TextOffset(1)))
  }

  @Test func audit036UnicodeSeparatorDoesNotInventALogicalLineBreak() {
    let value = TextInputValue(text: "界\u{2028}👩🏽‍💻z", selection: .caret(at: TextOffset(1)))
    let result = reduce(value, .deleteForward(granularity: .line))
    // The rendering contract treats CR/LF as breaks, not U+2028 (STUI-699).
    #expect(result.value.text == "界")
    #expect(result.value.selection == .caret(at: TextOffset(1)))
  }

  @Test func audit037SecureCopyAfterReplacementRemainsPrivate() {
    let replaced = TextInputReducer().reduce(
      TextInputValue(text: "old", selection: selection(0, 3)),
      command: .replaceSelection("new👩🏽‍💻"), traits: .secureField, layout: nil
    ).value
    let selected = reduce(replaced, .selectAll).value
    let copied = TextInputReducer().reduce(
      selected, command: .copySelection, traits: .secureField, layout: nil)
    #expect(copied.clipboardText == nil)
    #expect(copied.value == selected)
    #expect(!copied.shouldWriteBinding)
  }

  @Test func audit038SecureCutWithExtremeSelectionRemainsPrivate() {
    let value = TextInputValue(text: "secret🇺🇳", selection: selection(Int.max, 0))
    let cut = TextInputReducer().reduce(
      value, command: .cutSelection, traits: .secureField, layout: nil)
    #expect(cut.clipboardText == nil)
    #expect(cut.value.text == value.text)
    #expect(cut.value.selection == selection(value.text.count, 0))
    #expect(!cut.shouldWriteBinding)
  }

  @Test func audit039ExternalEmptyValueRetiresCompositionAndColumn() {
    let value = TextInputValue(
      text: "a👩🏽‍💻\nb", selection: selection(4, 1),
      composingRange: TextRange(TextOffset(1)..<TextOffset(2)), preferredVisualColumn: 90)
    let result = value.synchronized(with: "")
    #expect(result == TextInputValue())
    let inserted = reduce(result, .insertText("z"))
    #expect(inserted.value == TextInputValue(text: "z"))
  }

  @Test func audit040SelectionReplacementRetiresCompositionAndColumn() {
    let value = TextInputValue(
      text: "a👩🏽‍💻z", selection: selection(2, 1),
      composingRange: TextRange(TextOffset(1)..<TextOffset(2)), preferredVisualColumn: 90)
    let result = reduce(value, .replaceSelection("🇺🇳"))
    #expect(result.value.text == "a🇺🇳z")
    #expect(result.value.selection == .caret(at: TextOffset(2)))
    #expect(result.value.composingRange == nil)
    #expect(result.value.preferredVisualColumn == nil)
  }

  private func insertion(_ text: String, at: Int, insert: String, expected: String, caret: Int) {
    let result = reduce(
      TextInputValue(text: text, selection: .caret(at: TextOffset(at))), .insertText(insert))
    #expect(Array(result.value.text.unicodeScalars) == Array(expected.unicodeScalars))
    #expect(result.value.selection == .caret(at: TextOffset(caret)))
    #expect(result.value.selection.head.rawValue <= result.value.text.count)
    #expect(result.value.composingRange == nil)
  }

  private func selection(_ anchor: Int, _ head: Int) -> TextSelection {
    .init(anchor: TextOffset(anchor), head: TextOffset(head))
  }

  private func reduce(_ value: TextInputValue, _ command: TextInputCommand) -> TextInputMutation {
    TextInputReducer().reduce(value, command: command, traits: .multiline, layout: nil)
  }
}
