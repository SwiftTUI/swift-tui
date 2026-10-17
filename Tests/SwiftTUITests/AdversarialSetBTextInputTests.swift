// Adversarial set B, pass 2: text input (101–110).
//
// `TextInputReducer` owns caret and selection arithmetic, `TextInputPresentation`
// projects the value onto cells, and the run loop maps keys and assistive
// requests onto reducer commands. The probes here sit where those three
// disagree with AppKit's editing model or with each other: selection-modifying
// arrows, line breaks that are not `\n`, word boundaries with punctuation,
// vertical movement at the document ends, modified editing keys, the prompt of
// a focused field, overflow of a single-line field, and assistive writes that
// carry a newline into a single-line field.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: text input", .serialized)
struct AdversarialSetBTextInputTests {
  private static let fieldIdentity = testIdentity("SetBTextInput", "Field")
  private let reducer = TextInputReducer()

  private func reduce(
    _ value: TextInputValue, _ command: TextInputCommand, traits: TextInputTraits = .multiline,
    layout: TextInputLayoutMap? = nil
  ) -> TextInputMutation {
    reducer.reduce(value, command: command, traits: traits, layout: layout)
  }

  // Shift+Arrow moves the selection head by one cluster; it never flips the
  // selection to the other side of the anchor.
  @Test func setB101ShiftArrowWithASelectionMovesTheHeadOneCluster() throws {
    let forward = TextInputValue(
      text: "abcdefg", selection: TextSelection(anchor: TextOffset(2), head: TextOffset(5)))
    let shrink = reduce(forward, .move(.left, selecting: true)).value.selection
    let grow = reduce(forward, .move(.right, selecting: true)).value.selection
    #expect(grow == TextSelection(anchor: TextOffset(2), head: TextOffset(6)), "\(grow)")

    let backward = TextInputValue(
      text: "abcdefg", selection: TextSelection(anchor: TextOffset(5), head: TextOffset(2)))
    let shrinkBack = reduce(backward, .move(.right, selecting: true)).value.selection
    let growBack = reduce(backward, .move(.left, selecting: true)).value.selection
    #expect(growBack == TextSelection(anchor: TextOffset(5), head: TextOffset(1)), "\(growBack)")
    do {
      #expect(shrink == TextSelection(anchor: TextOffset(2), head: TextOffset(4)), "\(shrink)")
      #expect(
        shrinkBack == TextSelection(anchor: TextOffset(5), head: TextOffset(3)), "\(shrinkBack)")
    }

    // End to end: Home, select three clusters, give one back, type over it.
    let probe = SetBTextProbe("abcdefg")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBTextInput", "ShiftArrows"), size: .init(width: 30, height: 3)
    ) {
      TextField("Value", text: probe.binding()).id(Self.fieldIdentity).textFieldStyle(.plain)
    }
    defer { harness.shutdown() }
    _ = try harness.focus(Self.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.home))
    for _ in 0..<3 { _ = try harness.pressKey(KeyPress(.arrowRight, modifiers: .shift)) }
    _ = try harness.pressKey(KeyPress(.arrowLeft, modifiers: .shift))
    _ = try harness.pressKey(KeyPress(.character("X")))
    do {
      #expect(probe.value == "Xcdefg", "\(probe.value)")
    }
  }

  // A plain arrow with a selection collapses to the selection's edge; it does
  // not take an extra step past it.
  @Test func setB102PlainArrowWithASelectionCollapsesToItsEdge() {
    let selected = TextInputValue(
      text: "abcdefg", selection: TextSelection(anchor: TextOffset(2), head: TextOffset(5)))
    let left = reduce(selected, .move(.left, selecting: false)).value.selection
    let right = reduce(selected, .move(.right, selecting: false)).value.selection
    let reversed = TextInputValue(
      text: "abcdefg", selection: TextSelection(anchor: TextOffset(5), head: TextOffset(2)))
    do {
      #expect(left == .caret(at: TextOffset(2)), "\(left)")
      #expect(right == .caret(at: TextOffset(5)), "\(right)")
      #expect(
        reduce(reversed, .move(.left, selecting: false)).value.selection
          == .caret(at: TextOffset(2)))
      #expect(
        reduce(reversed, .move(.right, selecting: false)).value.selection
          == .caret(at: TextOffset(5)))
    }

    // At the document edges the collapse still lands on the edge.
    let atStart = TextInputValue(
      text: "abc", selection: TextSelection(anchor: TextOffset(0), head: TextOffset(2)))
    #expect(
      reduce(atStart, .move(.left, selecting: false)).value.selection == .caret(at: TextOffset(0)))
    let atEnd = TextInputValue(
      text: "abc", selection: TextSelection(anchor: TextOffset(1), head: TextOffset(3)))
    #expect(
      reduce(atEnd, .move(.right, selecting: false)).value.selection == .caret(at: TextOffset(3)))
  }

  // A CRLF grapheme is one line break for the caret map, the accessibility
  // anchor and the painted rows alike.
  @Test func setB103CRLFBreaksTheEditorRowWhereTheCaretMapBreaksIt() throws {
    for (name, text) in [("CRLF", "ab\r\ncd"), ("CR", "ab\rcd")] {
      let box = SetBTextProbe(text)
      let registry = LocalKeyHandlerRegistry()
      let identity = testIdentity("SetBTextInput", "Editor-\(name)")
      var environment = EnvironmentValues()
      environment.focusedIdentity = identity
      let renderer = DefaultRenderer()
      defer { withExtendedLifetime(renderer) {} }
      let artifacts = renderer.render(
        TextEditor(text: box.binding()).id(identity).frame(width: 10, height: 4),
        context: .init(
          identity: testIdentity("Root"), environmentValues: environment,
          localKeyHandlerRegistry: registry, applyEnvironmentValues: true))
      let lines = artifacts.rasterSurface.lines
      let node = try #require(
        artifacts.semanticSnapshot.accessibilityNodes.first { $0.role == .textEditor }, "\(name)")
      let anchor = try #require(node.cursorAnchor, "\(name)")
      let cdRow = lines.firstIndex { $0.contains("cd") }
      let abRow = lines.firstIndex { $0.contains("ab") }
      #expect(cdRow != nil && abRow != nil, "\(name): \(lines)")
      let controlCells = artifacts.rasterSurface.cells.flatMap { $0 }.filter {
        $0.character.unicodeScalars.contains { $0.value == 0x0D || $0.value == 0x0A }
      }
      do {
        #expect(cdRow != abRow, "\(name): the break puts cd on its own row: \(lines)")
        #expect(
          cdRow == anchor.y,
          "\(name): caret row \(anchor.y) vs painted row \(String(describing: cdRow))")
        #expect(
          controlCells.isEmpty, "\(name) painted a control scalar: \(controlCells.map(\.character))"
        )
      }
    }
  }

  // Home and End stop at every line break the editor draws, including CR and
  // CRLF, and line-granular deletion stops there too.
  @Test func setB104HomeAndEndHonorCRAndCRLFLineBreaks() {
    let crlf = TextInputValue(text: "ab\r\ncd", selection: .caret(at: TextOffset(4)))
    let lineStart = reduce(crlf, .move(.lineStart, selecting: false)).value.selection
    let firstLine = TextInputValue(text: "ab\r\ncd", selection: .caret(at: TextOffset(1)))
    let lineEnd = reduce(firstLine, .move(.lineEnd, selecting: false)).value.selection
    let cr = TextInputValue(text: "a\rb", selection: .caret(at: TextOffset(3)))
    let crFirst = TextInputValue(text: "a\rb", selection: .caret(at: TextOffset(0)))
    let deleted = reduce(crlf, .deleteBackward(granularity: .line)).value.text
    do {
      #expect(lineStart == .caret(at: TextOffset(3)), "\(lineStart)")
      #expect(lineEnd == .caret(at: TextOffset(2)), "\(lineEnd)")
      #expect(
        reduce(cr, .move(.lineStart, selecting: false)).value.selection == .caret(at: TextOffset(2))
      )
      #expect(
        reduce(crFirst, .move(.lineEnd, selecting: false)).value.selection
          == .caret(at: TextOffset(1)))
      #expect(deleted == "ab\r\nd", "\(deleted)")
    }
    let lf = TextInputValue(text: "ab\ncd", selection: .caret(at: TextOffset(4)))
    #expect(
      reduce(lf, .move(.lineStart, selecting: false)).value.selection == .caret(at: TextOffset(3)))
  }

  // Up on the first visual row moves to the document start and Down on the
  // last row to the document end, as AppKit's editors do.
  @Test func setB105VerticalMovementAtTheEdgesReachesTheDocumentEnds() {
    let top = TextInputValue(text: "abcd\nef", selection: .caret(at: TextOffset(2)))
    let topPresentation = TextInputPresentation(
      value: top, traits: .multiline, prompt: nil, isFocused: true, cursorFollowsFocus: false,
      width: 10)
    let up = reduce(top, .move(.up, selecting: false), layout: topPresentation.layoutMap)
    let bottom = TextInputValue(text: "abcd\nef", selection: .caret(at: TextOffset(6)))
    let bottomPresentation = TextInputPresentation(
      value: bottom, traits: .multiline, prompt: nil, isFocused: true, cursorFollowsFocus: false,
      width: 10)
    let down = reduce(bottom, .move(.down, selecting: false), layout: bottomPresentation.layoutMap)
    // Shift+Up from the first row selects back to the start.
    let selectUp = reduce(top, .move(.up, selecting: true), layout: topPresentation.layoutMap)
    do {
      #expect(up.value.selection == .caret(at: TextOffset(0)), "\(up.value.selection)")
      #expect(down.value.selection == .caret(at: TextOffset(7)), "\(down.value.selection)")
      #expect(
        selectUp.value.selection == TextSelection(anchor: TextOffset(2), head: TextOffset(0)),
        "\(selectUp.value.selection)")
    }

    // Ordinary vertical moves between rows keep working.
    let middle = TextInputValue(text: "abcd\nef\ngh", selection: .caret(at: TextOffset(6)))
    let middlePresentation = TextInputPresentation(
      value: middle, traits: .multiline, prompt: nil, isFocused: true, cursorFollowsFocus: false,
      width: 10)
    #expect(
      reduce(middle, .move(.up, selecting: false), layout: middlePresentation.layoutMap).value
        .selection == .caret(at: TextOffset(1)))
  }

  // Word movement treats an apostrophe or a decimal point between letters or
  // digits as part of the word, as UAX #29 and the wrapper's own token rule do.
  @Test func setB106WordBoundariesKeepMidWordPunctuation() {
    let contraction = TextInputValue(text: "don't stop", selection: .caret(at: TextOffset(5)))
    let back = reduce(contraction, .move(.wordBackward, selecting: false)).value.selection
    let deleted = reduce(contraction, .deleteBackward(granularity: .word)).value.text
    let fromStart = TextInputValue(text: "don't stop", selection: .caret(at: TextOffset(0)))
    let forward = reduce(fromStart, .move(.wordForward, selecting: false)).value.selection
    let decimal = TextInputValue(text: "3.14 x", selection: .caret(at: TextOffset(4)))
    let decimalBack = reduce(decimal, .move(.wordBackward, selecting: false)).value.selection
    do {
      #expect(back == .caret(at: TextOffset(0)), "\(back)")
      #expect(deleted == " stop", "\(deleted)")
      #expect(forward == .caret(at: TextOffset(5)), "\(forward)")
      #expect(decimalBack == .caret(at: TextOffset(0)), "\(decimalBack)")
    }

    // A trailing apostrophe or a space is still a boundary.
    let quoted = TextInputValue(text: "abc' def", selection: .caret(at: TextOffset(8)))
    let quotedBack = reduce(quoted, .move(.wordBackward, selecting: false)).value.selection
    #expect(quotedBack == .caret(at: TextOffset(5)), "\(quotedBack)")
  }

  // Shift+Backspace and Shift+Delete delete like their unmodified keys; a
  // terminal that reports the shift bit must not turn them into no-ops.
  @Test func setB107ShiftedDeleteKeysStillDelete() throws {
    let shiftBackspace = textInputCommand(
      for: KeyPress(.backspace, modifiers: .shift), traits: .singleLine)
    let shiftDelete = textInputCommand(
      for: KeyPress(.delete, modifiers: .shift), traits: .multiline)
    do {
      #expect(
        shiftBackspace == .deleteBackward(granularity: .character),
        "\(String(describing: shiftBackspace))")
      #expect(
        shiftDelete == .deleteForward(granularity: .character), "\(String(describing: shiftDelete))"
      )
    }

    let probe = SetBTextProbe("abc")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBTextInput", "ShiftBackspace"),
      size: .init(width: 30, height: 3)
    ) {
      TextField("Value", text: probe.binding()).id(Self.fieldIdentity).textFieldStyle(.plain)
    }
    defer { harness.shutdown() }
    _ = try harness.focus(Self.fieldIdentity)
    _ = try harness.pressKey(KeyPress(.backspace, modifiers: .shift))
    let afterBackspace = probe.value
    _ = try harness.pressKey(KeyPress(.home))
    _ = try harness.pressKey(KeyPress(.delete, modifiers: .shift))
    let afterDelete = probe.value
    do {
      #expect(afterBackspace == "ab", "\(afterBackspace)")
      #expect(afterDelete == "b", "\(afterDelete)")
    }
  }

  // The prompt of an empty field stays visible while the field has focus.
  @Test func setB108PromptOfAnEmptyFieldStaysVisibleWhileFocused() {
    let box = SetBTextProbe("")
    let identity = testIdentity("SetBTextInput", "Prompt")
    for focused in [false, true] {
      let registry = LocalKeyHandlerRegistry()
      var environment = EnvironmentValues()
      if focused { environment.focusedIdentity = identity }
      let renderer = DefaultRenderer()
      defer { withExtendedLifetime(renderer) {} }
      let artifacts = renderer.render(
        TextField("Name", text: box.binding()).id(identity).textFieldStyle(.plain),
        context: .init(
          identity: testIdentity("Root"), environmentValues: environment,
          localKeyHandlerRegistry: registry, applyEnvironmentValues: true),
        proposal: .init(width: 20, height: 1))
      let line = artifacts.rasterSurface.lines.first ?? ""
      do {
        #expect(line.contains("Name"), "focused=\(focused): \(artifacts.rasterSurface.lines)")
      }
    }
  }

  // A single-line field keeps its content inside its frame and the caret in
  // view; content wider than the frame scrolls, it does not spill over.
  @Test func setB109SingleLineFieldClipsToItsFrameAndKeepsTheCaretVisible() {
    let box = SetBTextProbe("abcdefghij")
    let identity = testIdentity("SetBTextInput", "Overflow")
    let registry = LocalKeyHandlerRegistry()
    var environment = EnvironmentValues()
    environment.focusedIdentity = identity
    let renderer = DefaultRenderer()
    defer { withExtendedLifetime(renderer) {} }
    let artifacts = renderer.render(
      HStack(spacing: 0) {
        TextField("N", text: box.binding()).id(identity).textFieldStyle(.plain)
          .frame(width: 5, alignment: .leading)
        Text("|")
      },
      context: .init(
        identity: testIdentity("Root"), environmentValues: environment,
        localKeyHandlerRegistry: registry, applyEnvironmentValues: true),
      proposal: .init(width: 20, height: 1))
    let line = artifacts.rasterSurface.lines.first ?? ""
    let barIndex = line.firstIndex(of: "|").map { line.distance(from: line.startIndex, to: $0) }
    #expect(barIndex == 5, "the field occupies five cells: \(line)")
    let field = String(line.prefix(5))
    do {
      #expect(field.contains("j") || field.contains("_"), "the caret end is in view: \(line)")
      #expect(!line.contains("abcde"), "the leading content scrolled out of view: \(line)")
    }
  }

  // An assistive `setValue` that carries a newline into a single-line field is
  // rejected as a whole, like `editText`, instead of being silently stripped.
  @Test func setB110AssistiveSetValueWithANewlineIsRejectedBySingleLineFields() throws {
    let probe = SetBTextProbe("")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBTextInput", "SetValue"), size: .init(width: 40, height: 3)
    ) {
      TextField("Value", text: probe.binding()).id(Self.fieldIdentity).textFieldStyle(.plain)
    }
    defer { harness.shutdown() }
    let node = try #require(
      harness.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .textField
      })
    let target = try #require(node.actionTarget)
    func send(_ action: AccessibilityAction) throws -> AccessibilityActionResult {
      let result = harness.runLoop.handleAccessibilityAction(.init(target: target, action: action))
      _ = try harness.renderAfterExternalMutation()
      return result
    }
    let rejected = try send(.setValue(.text("a\nb")))
    let writesAfterLF = probe.writes
    let crlf = try send(.setValue(.text("a\r\nb")))
    let writesAfterCRLF = probe.writes
    do {
      #expect(rejected == .invalidValue, "\(rejected)")
      #expect(writesAfterLF.isEmpty, "\(writesAfterLF)")
      #expect(crlf == .invalidValue, "\(crlf)")
      #expect(writesAfterCRLF.isEmpty, "\(writesAfterCRLF)")
    }
    probe.writes.removeAll()
    let accepted = try send(.setValue(.text("cd")))
    #expect(accepted == .accepted, "\(accepted)")
    #expect(probe.writes == ["cd"], "\(probe.writes)")
  }
}

@MainActor
private final class SetBTextProbe {
  var value: String
  var writes: [String] = []

  init(_ value: String) {
    self.value = value
  }

  func binding() -> Binding<String> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      })
  }
}
