import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetAEditorRuntimeTests {
  @Test func setA476DirectedUTF16EditTargetsTheSelectedGrapheme() throws {
    // Hypothesis: native UTF-16 selection direction is lost when routed to grapheme editing state.
    let box = EditorBoundaryBox("A🦊B")
    let h = try field(476, box)
    defer { h.shutdown() }
    #expect(try send(.editText(.init(text: box.text, anchor: 3, head: 1)), in: h) == .accepted)
    let selection = try #require(editor(in: h).textInput)
    #expect(selection.selection == 1..<3 && selection.insertionOffset == 1)
    try h.pressKey(.init(.character("X")))
    #expect(box.text == "AXB")
  }

  @Test func setA477SplitGraphemeEditsAreRejectedBeforeAnyBindingWrite() throws {
    // Hypothesis: directed-edit validation accepts a UTF-16 boundary inside a complete source grapheme.
    let box = EditorBoundaryBox("original")
    let h = try field(477, box)
    defer { h.shutdown() }
    for invalid in [
      AccessibilityTextEdit(text: "A🦊B", anchor: 2, head: 2),
      .init(text: "Ae\u{301}B", anchor: 2, head: 2),
      .init(text: "A👩‍💻B", anchor: 3, head: 3),
    ] {
      #expect(try send(.editText(invalid), in: h) == .invalidValue)
    }
    #expect(box.text == "original" && box.writes == 0)
  }

  @Test func setA478SelectionReviewRejectsAnObsoleteTextSnapshot() throws {
    // Hypothesis: an old native selection range selects unrelated replacement text of the same length.
    let box = EditorBoundaryBox("before")
    let h = try field(478, box)
    defer { h.shutdown() }
    box.text = "after!"
    try h.renderAfterExternalMutation()
    #expect(
      try send(.selectText(.init(text: "before", anchor: 0, head: 2)), in: h) == .invalidValue)
    try h.pressKey(.init(.character("X")))
    #expect(box.text == "after!X")
    #expect(box.writes == 1)
  }

  @Test func setA479SingleLineDirectedEditRejectsLineBreaksAtomically() throws {
    // Hypothesis: an edit with line breaks is partially sanitized before its native selection is rejected.
    let box = EditorBoundaryBox("old")
    let h = try field(479, box)
    defer { h.shutdown() }
    #expect(try send(.editText(.init(text: "a\nb", anchor: 3, head: 3)), in: h) == .invalidValue)
    #expect(box.text == "old" && box.writes == 0)
    try h.pressKey(.init(.character("X")))
    #expect(box.text == "oldX")
  }

  @Test func setA480SelectionOnlyReviewDoesNotWriteTheModel() throws {
    // Hypothesis: selecting native text routes through replacement and invokes an observable binding setter.
    let box = EditorBoundaryBox("abcde")
    let h = try field(480, box)
    defer { h.shutdown() }
    #expect(try send(.selectText(.init(text: box.text, anchor: 1, head: 4)), in: h) == .accepted)
    #expect(box.writes == 0)
    try h.pressKey(.init(.delete))
    #expect(box.text == "ae" && box.writes == 1)
  }

  @Test func setA481ReplacementAndCaretAreCommittedAsOneNativeEdit() throws {
    // Hypothesis: replacing text schedules a frame that overwrites the directed edit's requested caret.
    let box = EditorBoundaryBox("old")
    let h = try field(481, box)
    defer { h.shutdown() }
    #expect(try send(.editText(.init(text: "new text", anchor: 3, head: 3)), in: h) == .accepted)
    #expect(box.writes == 1)
    #expect(try editor(in: h).textInput?.insertionOffset == 3)
    try h.pressKey(.init(.character("!")))
    #expect(box.text == "new! text" && box.writes == 2)
  }

  @Test func setA482SecureDirectedEditsNeverPublishTheirTextGeometry() throws {
    // Hypothesis: native edit support adds ordinary text metadata to a secure control after its first mutation.
    let box = EditorBoundaryBox("initial")
    let h = try make(482) { SecureField("Secret", text: box.binding) }
    defer { h.shutdown() }
    #expect(try send(.editText(.init(text: "hidden🦊", anchor: 8, head: 8)), in: h) == .accepted)
    let node = try editor(in: h)
    #expect(node.textInput == nil && node.control?.value == nil)
    #expect(!h.frame.contains("hidden"))
    #expect(box.text == "hidden🦊")
  }

  @Test func setA483FailedClipboardCutPreservesTextAndSelection() throws {
    // Hypothesis: cut commits deletion before the host accepts the clipboard write.
    let box = EditorBoundaryBox("abcde")
    let h = try make(483) {
      TextField("Edit", text: box.binding).environment(
        \.clipboardWriteAction,
        ClipboardWriteAction {
          box.copied.append($0)
          return false
        })
    }
    defer { h.shutdown() }
    #expect(try send(.selectText(.init(text: box.text, anchor: 1, head: 4)), in: h) == .accepted)
    try h.pressKey(.init(.character("x"), modifiers: .ctrl))
    #expect(box.copied == ["bcd"])
    #expect(box.text == "abcde" && box.writes == 0)
    #expect(try editor(in: h).textInput?.selection == 1..<4)
  }

  @Test func setA484ClipboardReadClosureRefreshesWithItsEnvironment() throws {
    // Hypothesis: a retained editor's paste handler captures an obsolete host clipboard provider.
    let box = EditorBoundaryBox("")
    let h = try make(484) {
      let captured = box.clipboard
      TextField("Edit", text: box.binding).environment(
        \.clipboardReadAction,
        ClipboardReadAction(
          snapshotLabel: "SetAClipboard", isPlaceholder: false, handler: { captured }))
    }
    defer { h.shutdown() }
    box.clipboard = "new provider"
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.character("v"), modifiers: .ctrl))
    #expect(box.text == "new provider" && box.writes == 1)
  }

  @Test func setA485SingleLinePasteFiltersAllNewlineScalarForms() throws {
    // Hypothesis: clipboard insertion lets paired CRLF survive single-line sanitization while isolated CR/LF disappear.
    let box = EditorBoundaryBox("a")
    let h = try field(485, box)
    defer { h.shutdown() }
    try h.paste("b\r\nc\rd\ne")
    #expect(box.text == "abcde" && box.writes == 1)
    #expect(try editor(in: h).textInput?.insertionOffset == 5)
  }

  @Test func setA486SecureCutDoesNotReachTheHostClipboard() throws {
    // Hypothesis: runtime clipboard dispatch bypasses the secure reducer's cut suppression.
    let box = EditorBoundaryBox("sensitive")
    let h = try make(486) {
      SecureField("Secret", text: box.binding).environment(
        \.clipboardWriteAction,
        ClipboardWriteAction {
          box.copied.append($0)
          return true
        })
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.character("a"), modifiers: .ctrl))
    try h.pressKey(.init(.character("x"), modifiers: .ctrl))
    #expect(box.copied.isEmpty && box.writes == 0)
    #expect(box.text == "sensitive")
  }

  @Test func setA487RejectedTextWriteCannotSeedTheNextEdit() throws {
    // Hypothesis: optimistic local editing state accumulates rejected binding mutations into a later accepted edit.
    let box = EditorBoundaryBox("a")
    let h = try make(487) {
      TextField("Edit", text: Binding(get: { box.text }, set: { box.attempts.append($0) }))
    }
    defer { h.shutdown() }
    try h.pressKey(.init(.character("X")))
    try h.pressKey(.init(.character("Y")))
    #expect(box.attempts == ["aX", "aY"])
    #expect(box.text == "a")
  }

  @Test func setA488ExternalReplacementRetiresTheOldCaret() throws {
    // Hypothesis: an external text replacement carries a selection offset from the old document into unrelated text.
    let box = EditorBoundaryBox("abcdef")
    let h = try field(488, box)
    defer { h.shutdown() }
    #expect(try send(.selectText(.init(text: box.text, anchor: 1, head: 1)), in: h) == .accepted)
    box.text = "xy"
    try h.renderAfterExternalMutation()
    try h.pressKey(.init(.character("Z")))
    #expect(box.text == "xyZ")
  }

  @Test func setA489SiblingEditorsKeepIndependentCaretSlots() throws {
    // Hypothesis: moving focus between two editors aliases their retained caret storage.
    let first = EditorBoundaryBox("abc")
    let second = EditorBoundaryBox("uvw")
    let h = try make(489) {
      VStack {
        TextField("First", text: first.binding)
        TextField("Second", text: second.binding)
      }
    }
    defer { h.shutdown() }
    let nodes = h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter {
      $0.role == .textField
    }
    #expect(nodes.count == 2)
    let firstNode = try #require(nodes.first)
    let secondNode = try #require(nodes.last)
    #expect(
      try send(.selectText(.init(text: "abc", anchor: 1, head: 1)), node: firstNode, in: h)
        == .accepted)
    #expect(try send(.focus, node: secondNode, in: h) == .accepted)
    try h.pressKey(.init(.arrowLeft))
    #expect(try send(.focus, node: firstNode, in: h) == .accepted)
    try h.pressKey(.init(.character("X")))
    #expect(first.text == "aXbc" && second.text == "uvw")
  }

  @Test func setA490HorizontalMoveResetsAnEditorsPreferredVerticalColumn() throws {
    // Hypothesis: a horizontal edit leaves the prior tall-line column sticky during the next vertical move.
    let box = EditorBoundaryBox("abcd\nx\nabcdef")
    let h = try make(490) { TextEditor(text: box.binding).frame(width: 30, height: 8) }
    defer { h.shutdown() }
    #expect(try send(.selectText(.init(text: box.text, anchor: 3, head: 3)), in: h) == .accepted)
    try h.pressKey(.init(.arrowDown))
    try h.pressKey(.init(.arrowLeft))
    try h.pressKey(.init(.arrowDown))
    try h.pressKey(.init(.character("X")))
    #expect(box.text == "abcd\nx\nXabcdef")
  }

  @Test func setA491SecureProjectionCountsGraphemesInsteadOfSourceCellWidths() {
    // Hypothesis: masking keeps the original emoji/wide-cell widths and leaks source geometry through the caret.
    let p = presentation("🦊界a", traits: .secureField)
    #expect(p.displayText == "•••")
    #expect(p.caretAnchor == CellPoint(x: 3, y: 0))
    #expect(p.layoutMap.contentSize.width == 3)
  }

  @Test func setA492UnfocusedEditorDoesNotPaintItsRetainedSelection() {
    // Hypothesis: selection highlighting remains visible after the owning editor loses focus.
    let value = TextInputValue(text: "abcd", selection: .init(anchor: .init(1), head: .init(3)))
    let p = TextInputPresentation(
      value: value, traits: .singleLine, prompt: nil,
      isFocused: false, cursorFollowsFocus: false, width: 12)
    #expect(p.displayText == "abcd")
    #expect(p.displayRuns.allSatisfy { !$0.isSelected })
    #expect(!p.shouldDrawSyntheticCaret)
  }

  @Test func setA493PromptGlyphsNeverAcquireEditableSourceOffsets() {
    // Hypothesis: a long prompt advances the empty field's source caret or creates selectable source text.
    let p = TextInputPresentation(
      value: .init(), traits: .singleLine, prompt: "Wide 界 prompt",
      isFocused: false, cursorFollowsFocus: false, width: nil)
    #expect(p.isShowingPrompt && p.displayText == "Wide 界 prompt")
    #expect(p.layoutMap.lines.flatMap(\.clusters).allSatisfy { $0.textRange.isEmpty })
    #expect(p.layoutMap.nearestOffset(to: .init(x: 8, y: 0)) == TextOffset(0))
  }

  @Test func setA494WrappedSelectionExcludesSyntheticMarkerCells() {
    // Hypothesis: selecting an entire long word highlights synthesized wrap markers as source characters.
    let p = presentation("abcdefghijk", width: 5)
    let rectangles = p.layoutMap.selectionRects(for: .init(TextOffset(0)..<TextOffset(11)))
    #expect(p.layoutMap.lines.count > 1)
    #expect(rectangles.count == p.layoutMap.lines.count)
    for (line, rect) in zip(p.layoutMap.lines, rectangles) {
      #expect(rect.origin.x == line.clusters.first?.originX)
      #expect(rect.size.width == line.clusters.reduce(0) { $0 + $1.cellWidth })
    }
  }

  @Test func setA495SwallowedWrapWhitespaceKeepsThePreviousRowsCaret() {
    // Hypothesis: a source offset in discarded wrapping whitespace jumps to the next visual row.
    let p = presentation("A  B", width: 2)
    #expect(p.layoutMap.lines.count == 2)
    #expect(p.layoutMap.caretPoint(for: .init(2)) == CellPoint(x: 1, y: 0))
  }

  @Test func setA496VerticalTravelRecoversThePreferredColumnAfterAShortRow() {
    // Hypothesis: clamping to a short intermediate line destroys the preferred column for the next line.
    let p = presentation("abcd\nx\nabcdef")
    let short = p.layoutMap.verticalOffset(from: .init(3), delta: 1, preferredVisualColumn: nil)
    let long = p.layoutMap.verticalOffset(
      from: short.offset, delta: 1,
      preferredVisualColumn: short.preferredVisualColumn)
    #expect(short.offset == TextOffset(6))
    #expect(long.offset == TextOffset(10))
  }

  @Test func setA497WideGlyphHitTestingUsesItsCellMidpoint() {
    // Hypothesis: cell hit testing treats a wide grapheme as two editable characters.
    let map = presentation("界x").layoutMap
    #expect(map.nearestOffset(to: .init(x: 0, y: 0)) == TextOffset(0))
    #expect(map.nearestOffset(to: .init(x: 1, y: 0)) == TextOffset(1))
    #expect(map.nearestOffset(to: .init(x: 2, y: 0)) == TextOffset(1))
  }

  @Test func setA498TrailingNewlineRetainsAnEmptyEditableRow() {
    // Hypothesis: layout omits the final empty row and returns a caret before the document's final newline.
    let p = presentation("ab\n")
    #expect(p.layoutMap.lines.count == 2)
    #expect(p.caretAnchor == CellPoint(x: 0, y: 1))
    #expect(p.layoutMap.nearestOffset(to: .init(x: 20, y: 50)) == TextOffset(3))
  }

  @Test func setA499SyntheticNewlineCaretDoesNotShiftTheNativeEndAnchor() {
    // Hypothesis: native geometry counts a synthetic caret cell as an additional source character.
    let metadata = accessibilityTextInput(
      .init(text: "a\nb", anchor: 1, head: 1, displayText: "a_\nb"),
      bounds: .init(origin: .init(x: 5, y: 7), size: .init(width: 20, height: 3)), wraps: true)
    #expect(metadata.clusters.count == 3)
    #expect(metadata.insertionOffset == 1)
    #expect(metadata.endAnchor == CellPoint(x: 6, y: 8))
  }

  @Test func setA500NativeClusterRangesUseUTF16WhileWidthsUseCells() {
    // Hypothesis: a source range calculation reuses terminal widths for combining and supplementary characters.
    let metadata = accessibilityTextInput(
      .init(text: "e\u{301}🦊界", anchor: 0, head: 3),
      bounds: .init(origin: .init(x: 4, y: 2), size: .init(width: 20, height: 1)), wraps: false)
    #expect(metadata.clusters.map(\.range) == [0..<2, 2..<4, 4..<5])
    #expect(metadata.clusters.map { $0.rect.size.width } == [1, 2, 2])
    #expect(metadata.insertionOffset == 5 && metadata.selection == 0..<5)
  }

  private func presentation(_ text: String, traits: TextInputTraits = .multiline, width: Int? = nil)
    -> TextInputPresentation
  {
    TextInputPresentation(
      value: .init(text: text), traits: traits, prompt: nil,
      isFocused: true, cursorFollowsFocus: true, width: width)
  }

  private func field(_ number: Int, _ box: EditorBoundaryBox) throws -> StressRuntimeHarness<
    TextField<EmptyView>
  > {
    try make(number) { TextField("Edit", text: box.binding) }
  }

  private func make<V: View>(_ number: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAEditor\(number)"),
      size: .init(width: 60, height: 16), content: content)
  }

  private func editor<V: View>(in h: StressRuntimeHarness<V>) throws -> AccessibilityNode {
    try #require(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .textField || $0.role == .textEditor || $0.role == .secureField
      })
  }

  private func send<V: View>(
    _ action: AccessibilityAction, node: AccessibilityNode? = nil,
    in h: StressRuntimeHarness<V>
  ) throws -> AccessibilityActionResult {
    let target = try node ?? editor(in: h)
    let result = h.runLoop.handleAccessibilityAction(
      .init(target: try #require(target.actionTarget), action: action))
    try h.render()
    return result
  }
}

@MainActor
private final class EditorBoundaryBox {
  var text: String
  var writes = 0
  var copied: [String] = []
  var attempts: [String] = []
  var clipboard = "old provider"
  init(_ text: String) { self.text = text }
  var binding: Binding<String> {
    Binding(
      get: { self.text },
      set: {
        self.text = $0
        self.writes += 1
      })
  }
}
