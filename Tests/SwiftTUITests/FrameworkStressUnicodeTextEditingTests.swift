import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Suite("SwiftTUI Unicode text-editing stress behavior", .serialized)
struct FrameworkStressUnicodeTextEditingTests {}

// MARK: - Grapheme-safe editing

extension FrameworkStressUnicodeTextEditingTests {
  @Test("stress Unicode editing 001 backspace removes one family grapheme")
  func unicodeEditing001BackspaceRemovesOneFamilyGrapheme() {
    // Hypothesis: backward deletion can split a multi-scalar ZWJ family instead of removing the
    // single user-perceived character immediately before the caret.
    let family = "👨‍👩‍👧‍👦"
    let value = TextInputValue(
      text: "A\(family)B",
      selection: .caret(at: TextOffset(2))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteBackward(granularity: .character),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "AB")
    #expect(mutation.value.selection == .caret(at: TextOffset(1)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(2)))
  }

  @Test("stress Unicode editing 002 forward delete removes one flag grapheme")
  func unicodeEditing002ForwardDeleteRemovesOneFlagGrapheme() {
    // Hypothesis: forward deletion can treat a regional-indicator pair as two editable units.
    let value = TextInputValue(
      text: "A🇺🇳B",
      selection: .caret(at: TextOffset(1))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteForward(granularity: .character),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "AB")
    #expect(mutation.value.selection == .caret(at: TextOffset(1)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(2)))
  }

  @Test("stress Unicode editing 003 reversed selection replaces whole keycap")
  func unicodeEditing003ReversedSelectionReplacesWholeKeycap() {
    // Hypothesis: normalizing a backward selection can expose the scalar interior of a keycap
    // grapheme and leave variation-selector debris after replacement.
    let value = TextInputValue(
      text: "A1️⃣B",
      selection: TextSelection(anchor: TextOffset(2), head: TextOffset(1))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .replaceSelection("界"),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "A界B")
    #expect(mutation.value.selection == .caret(at: TextOffset(2)))
    #expect(mutation.insertedText == "界")
  }

  @Test("stress Unicode editing 004 inserted decomposed cluster advances one offset")
  func unicodeEditing004InsertedDecomposedClusterAdvancesOneOffset() {
    // Hypothesis: insertion can advance the caret by Unicode-scalar count instead of extended
    // grapheme count when the inserted glyph uses a combining mark.
    let decomposed = "e\u{0301}"
    let value = TextInputValue(text: "AB", selection: .caret(at: TextOffset(1)))

    let mutation = TextInputReducer().reduce(
      value,
      command: .insertText(decomposed),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "A\(decomposed)B")
    #expect(mutation.value.text.count == 3)
    #expect(mutation.value.selection == .caret(at: TextOffset(2)))
    #expect(mutation.changedRange == TextRange(TextOffset(1)..<TextOffset(2)))
  }

  @Test("stress Unicode editing 005 single-line CRLF filtering preserves adjacent graphemes")
  func unicodeEditing005SingleLineCRLFFilteringPreservesAdjacentGraphemes() {
    // Hypothesis: scalar-level CR/LF filtering can accidentally split either neighboring emoji
    // grapheme while removing a coalesced CRLF Character.
    let value = TextInputValue(text: "A", selection: .caret(at: TextOffset(1)))

    let mutation = TextInputReducer().reduce(
      value,
      command: .insertText("👋🏿\r\n1️⃣"),
      traits: .singleLine,
      layout: nil
    )

    #expect(mutation.value.text == "A👋🏿1️⃣")
    #expect(mutation.value.text.count == 3)
    #expect(mutation.value.selection == .caret(at: TextOffset(3)))
    #expect(!mutation.insertedText.unicodeScalars.contains { $0.value == 0x0A || $0.value == 0x0D })
  }

  @Test("stress Unicode editing 006 CRLF produces one multiline break")
  func unicodeEditing006CRLFProducesOneMultilineBreak() {
    // Hypothesis: Swift's coalesced CRLF Character can bypass newline projection and render as an
    // in-line control cluster instead of one visual line break.
    let presentation = unicodePresentation(text: "界\r\nB", caret: 2, width: nil)

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(2)) == CellPoint(x: 0, y: 1))
    #expect(presentation.layoutMap.contentSize == CellSize(width: 2, height: 2))
  }

  @Test("stress Unicode editing 007 carriage return produces a multiline break")
  func unicodeEditing007CarriageReturnProducesAMultilineBreak() {
    // Hypothesis: a pasted classic-Mac carriage return can remain embedded in a visual line even
    // though multiline input should treat it as a line separator.
    let presentation = unicodePresentation(text: "A\r界", caret: 2, width: nil)

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.caretPoint(for: TextOffset(2)) == CellPoint(x: 0, y: 1))
    #expect(presentation.layoutMap.contentSize == CellSize(width: 2, height: 2))
  }

  @Test("stress Unicode editing 008 word movement recognizes a Devanagari grapheme")
  func unicodeEditing008WordMovementRecognizesADevanagariGrapheme() {
    // Hypothesis: word classification can reject a multi-scalar alphabetic grapheme when its
    // vowel mark is non-alphabetic, skipping the whole word during backward movement.
    let text = "go नमस्ते"
    let value = TextInputValue(text: text, selection: .caret(at: TextOffset(text.count)))

    let mutation = TextInputReducer().reduce(
      value,
      command: .move(.wordBackward, selecting: false),
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.selection == .caret(at: TextOffset(3)))
  }

  @Test("stress Unicode editing 009 word deletion recognizes Arabic-Indic digits")
  func unicodeEditing009WordDeletionRecognizesArabicIndicDigits() {
    // Hypothesis: numeric word classification can be ASCII-only and delete punctuation plus the
    // following suffix when an Arabic-Indic digit run begins at the caret.
    let value = TextInputValue(text: "١٢٣,tail", selection: .caret(at: TextOffset(0)))

    let mutation = TextInputReducer().reduce(
      value,
      command: .deleteForward(granularity: .word),
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.value.text == ",tail")
    #expect(mutation.changedRange == TextRange(TextOffset(0)..<TextOffset(3)))
  }

  @Test("stress Unicode editing 010 cut copies exact emoji grapheme spelling")
  func unicodeEditing010CutCopiesExactEmojiGraphemeSpelling() {
    // Hypothesis: selection extraction can normalize or partially slice a skin-tone ZWJ grapheme
    // before placing it on the clipboard.
    let astronaut = "👩🏽‍🚀"
    let value = TextInputValue(
      text: "A\(astronaut)B",
      selection: TextSelection(anchor: TextOffset(1), head: TextOffset(2))
    )

    let mutation = TextInputReducer().reduce(
      value,
      command: .cutSelection,
      traits: .multiline,
      layout: nil
    )

    #expect(mutation.clipboardText == astronaut)
    #expect(mutation.value.text == "AB")
    #expect(mutation.value.selection == .caret(at: TextOffset(1)))
  }
}

// MARK: - Unicode projection and geometry

extension FrameworkStressUnicodeTextEditingTests {
  @Test("stress Unicode editing 011 secure masking counts graphemes not scalars")
  func unicodeEditing011SecureMaskingCountsGraphemesNotScalars() {
    // Hypothesis: secure projection can leak the scalar complexity of a secret by drawing more
    // than one mask cell for a multi-scalar grapheme.
    let secret = "e\u{0301}👨‍👩‍👧‍👦🇺🇳1️⃣"
    let presentation = TextInputPresentation(
      value: TextInputValue(text: secret, selection: .caret(at: TextOffset(secret.count))),
      traits: .secureField,
      prompt: nil,
      isFocused: true,
      cursorFollowsFocus: true,
      width: nil
    )

    #expect(secret.count == 4)
    #expect(presentation.displayText == "••••")
    #expect(presentation.layoutMap.contentSize == CellSize(width: 4, height: 1))
    #expect(presentation.caretAnchor == CellPoint(x: 4, y: 0))
  }

  @Test("stress Unicode editing 012 family emoji caret uses two terminal cells")
  func unicodeEditing012FamilyEmojiCaretUsesTwoTerminalCells() {
    // Hypothesis: layout can charge a ZWJ sequence per emoji scalar, pushing the caret far past
    // the two-cell terminal glyph.
    let presentation = unicodePresentation(text: "👨‍👩‍👧‍👦A", caret: 1, width: nil)

    #expect(presentation.caretAnchor == CellPoint(x: 2, y: 0))
    #expect(presentation.layoutMap.contentSize == CellSize(width: 3, height: 1))
    #expect(presentation.layoutMap.lines[0].clusters.count == 2)
  }

  @Test("stress Unicode editing 013 VS16 changes symbol caret width")
  func unicodeEditing013VS16ChangesSymbolCaretWidth() {
    // Hypothesis: two canonically related symbol presentations can share stale width metadata,
    // leaving text-style and emoji-style copyright signs with the same caret geometry.
    let textStyle = unicodePresentation(text: "©︎A", caret: 1, width: nil)
    let emojiStyle = unicodePresentation(text: "©️A", caret: 1, width: nil)

    #expect(textStyle.caretAnchor == CellPoint(x: 1, y: 0))
    #expect(textStyle.layoutMap.contentSize.width == 2)
    #expect(emojiStyle.caretAnchor == CellPoint(x: 2, y: 0))
    #expect(emojiStyle.layoutMap.contentSize.width == 3)
  }

  @Test("stress Unicode editing 014 regional-indicator flag occupies one wide cluster")
  func unicodeEditing014RegionalIndicatorFlagOccupiesOneWideCluster() {
    // Hypothesis: a flag can project as two regional-indicator cells while editing even though
    // rendering treats the pair as one two-cell grapheme.
    let presentation = unicodePresentation(text: "A🇯🇵B", caret: 2, width: nil)

    #expect(presentation.layoutMap.lines[0].clusters.count == 3)
    #expect(presentation.caretAnchor == CellPoint(x: 3, y: 0))
    #expect(presentation.layoutMap.contentSize == CellSize(width: 4, height: 1))
  }

  @Test("stress Unicode editing 015 keycap occupies one wide cluster")
  func unicodeEditing015KeycapOccupiesOneWideCluster() {
    // Hypothesis: enclosing-keycap and variation-selector scalars can be billed separately in the
    // editor layout map, making hit testing disagree with the rendered keycap.
    let presentation = unicodePresentation(text: "A1️⃣B", caret: 2, width: nil)

    #expect(presentation.layoutMap.lines[0].clusters.count == 3)
    #expect(presentation.caretAnchor == CellPoint(x: 3, y: 0))
    #expect(presentation.layoutMap.contentSize == CellSize(width: 4, height: 1))
  }

  @Test("stress Unicode editing 016 wide-cluster hit testing never returns an interior offset")
  func unicodeEditing016WideClusterHitTestingNeverReturnsAnInteriorOffset() {
    // Hypothesis: clicking the left and right cells of a wide grapheme can synthesize an offset
    // between its Unicode scalars, which the grapheme-indexed reducer cannot safely consume.
    let presentation = unicodePresentation(text: "A界B", caret: 0, width: nil)

    let leftCell = presentation.layoutMap.nearestOffset(to: CellPoint(x: 1, y: 0))
    let rightCell = presentation.layoutMap.nearestOffset(to: CellPoint(x: 2, y: 0))

    #expect(leftCell == TextOffset(1))
    #expect(rightCell == TextOffset(2))
  }

  @Test("stress Unicode editing 017 family selection rect spans full glyph")
  func unicodeEditing017FamilySelectionRectSpansFullGlyph() {
    // Hypothesis: selecting a ZWJ family can reverse-highlight only one cell because its source
    // range is one grapheme while its terminal footprint is two cells.
    let family = "👨‍👩‍👧‍👦"
    let presentation = unicodePresentation(
      text: "A\(family)B",
      selection: TextSelection(anchor: TextOffset(1), head: TextOffset(2)),
      width: nil
    )

    #expect(
      presentation.selectionRects
        == [CellRect(origin: CellPoint(x: 1, y: 0), size: CellSize(width: 2, height: 1))]
    )
    #expect(presentation.displayRuns.map(\.isSelected) == [false, true, false])
  }

  @Test("stress Unicode editing 018 wrapped selection rects preserve mixed cell widths")
  func unicodeEditing018WrappedSelectionRectsPreserveMixedCellWidths() {
    // Hypothesis: a range crossing a wrap after a wide glyph can reuse grapheme counts as cell
    // widths, shifting one of the selected rectangles.
    let presentation = unicodePresentation(
      text: "A界BC",
      selection: TextSelection(anchor: TextOffset(1), head: TextOffset(4)),
      width: 3
    )

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(
      presentation.selectionRects
        == [
          CellRect(origin: CellPoint(x: 1, y: 0), size: CellSize(width: 2, height: 1)),
          CellRect(origin: CellPoint(x: 0, y: 1), size: CellSize(width: 2, height: 1)),
        ]
    )
  }

  @Test("stress Unicode editing 019 vertical movement preserves a wide visual column")
  func unicodeEditing019VerticalMovementPreservesAWideVisualColumn() {
    // Hypothesis: moving down can use grapheme offset rather than terminal column after a CJK
    // glyph, landing one cell too far left on the ASCII line.
    let text = "界A\nxyz"
    let presentation = unicodePresentation(text: text, caret: 1, width: nil)
    let value = TextInputValue(text: text, selection: .caret(at: TextOffset(1)))

    let mutation = TextInputReducer().reduce(
      value,
      command: .move(.down, selecting: false),
      traits: .multiline,
      layout: presentation.layoutMap
    )

    #expect(mutation.value.selection == .caret(at: TextOffset(5)))
    #expect(mutation.value.preferredVisualColumn == 2)
  }

  @Test("stress Unicode editing 020 vertical round trip restores column after short line")
  func unicodeEditing020VerticalRoundTripRestoresColumnAfterShortLine() {
    // Hypothesis: clamping onto a short intermediate line can overwrite the preferred visual
    // column measured after a wide grapheme, preventing a later long-line round trip.
    let text = "界AB\nx\n1234"
    let presentation = unicodePresentation(text: text, caret: 3, width: nil)
    let reducer = TextInputReducer()
    let initial = TextInputValue(text: text, selection: .caret(at: TextOffset(3)))

    let shortLine = reducer.reduce(
      initial,
      command: .move(.down, selecting: false),
      traits: .multiline,
      layout: presentation.layoutMap
    ).value
    let longLine = reducer.reduce(
      shortLine,
      command: .move(.down, selecting: false),
      traits: .multiline,
      layout: presentation.layoutMap
    ).value

    #expect(shortLine.selection == .caret(at: TextOffset(5)))
    #expect(shortLine.preferredVisualColumn == 4)
    #expect(longLine.selection == .caret(at: TextOffset(10)))
    #expect(longLine.preferredVisualColumn == 4)
  }
}

// MARK: - Multiline boundaries and synchronization

extension FrameworkStressUnicodeTextEditingTests {
  @Test("stress Unicode editing 021 LF resets caret origin after a wide glyph")
  func unicodeEditing021LFResetsCaretOriginAfterAWideGlyph() {
    // Hypothesis: finishing a line after a wide grapheme can leak its cell width into the next
    // line's origin when an explicit LF is projected.
    let presentation = unicodePresentation(text: "界\nA", caret: 2, width: nil)

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.caretAnchor == CellPoint(x: 0, y: 1))
    #expect(presentation.layoutMap.lines[1].origin == CellPoint(x: 0, y: 1))
  }

  @Test("stress Unicode editing 022 trailing LF creates empty line after emoji")
  func unicodeEditing022TrailingLFCreatesEmptyLineAfterEmoji() {
    // Hypothesis: the builder can omit an empty final layout line when the preceding line ends in
    // a multi-scalar emoji rather than an ASCII cluster.
    let text = "👩🏽‍🚀\n"
    let presentation = unicodePresentation(text: text, caret: text.count, width: nil)

    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.lines[1].sourceRange == TextRange(TextOffset(2)..<TextOffset(2)))
    #expect(presentation.caretAnchor == CellPoint(x: 0, y: 1))
  }

  @Test("stress Unicode editing 023 Unicode prompt wraps without gaining source offsets")
  func unicodeEditing023UnicodePromptWrapsWithoutGainingSourceOffsets() {
    // Hypothesis: a wide prompt that wraps can acquire editable source ranges, allowing pointer
    // hit testing to place an empty field's caret at a nonexistent offset.
    let presentation = TextInputPresentation(
      value: TextInputValue(),
      traits: .singleLine,
      prompt: "界A",
      isFocused: false,
      cursorFollowsFocus: false,
      width: 2
    )

    #expect(presentation.isShowingPrompt)
    #expect(presentation.layoutMap.lines.count == 2)
    #expect(presentation.layoutMap.lines.allSatisfy { $0.sourceRange.isEmpty })
    #expect(presentation.layoutMap.nearestOffset(to: CellPoint(x: 1, y: 1)) == TextOffset(0))
  }

  @Test("stress Unicode editing 024 canonical rewrite preserves grapheme selection")
  func unicodeEditing024CanonicalRewritePreservesGraphemeSelection() {
    // Hypothesis: synchronizing canonically equivalent composed and decomposed spellings can reset
    // a valid grapheme selection even though Swift considers the visible text unchanged.
    let composed = "éA"
    let decomposed = "e\u{0301}A"
    let value = TextInputValue(
      text: composed,
      selection: TextSelection(anchor: TextOffset(0), head: TextOffset(1))
    )

    let synchronized = value.synchronized(with: decomposed)

    #expect(composed == decomposed)
    #expect(synchronized.selection == value.selection)
    #expect(synchronized.text.count == 2)
  }

  @Test("stress Unicode editing 025 selection clamps by grapheme count")
  func unicodeEditing025SelectionClampsByGraphemeCount() {
    // Hypothesis: clamping an out-of-range selection can use UTF-8 or scalar length for complex
    // graphemes, leaving offsets beyond the editable Character collection.
    let text = "👨‍👩‍👧‍👦e\u{0301}🇺🇳"
    let value = TextInputValue(
      text: text,
      selection: TextSelection(anchor: TextOffset(99), head: TextOffset(1))
    )

    let clamped = value.clampingSelection()

    #expect(text.count == 3)
    #expect(clamped.selection == TextSelection(anchor: TextOffset(3), head: TextOffset(1)))
    #expect(clamped.selection.range == TextRange(TextOffset(1)..<TextOffset(3)))
  }
}

private func unicodePresentation(
  text: String,
  caret: Int,
  width: Int?
) -> TextInputPresentation {
  unicodePresentation(
    text: text,
    selection: .caret(at: TextOffset(caret)),
    width: width
  )
}

private func unicodePresentation(
  text: String,
  selection: TextSelection,
  width: Int?
) -> TextInputPresentation {
  TextInputPresentation(
    value: TextInputValue(text: text, selection: selection),
    traits: .multiline,
    prompt: nil,
    isFocused: true,
    cursorFollowsFocus: true,
    width: width
  )
}
