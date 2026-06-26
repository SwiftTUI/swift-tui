import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Coverage for VT220 "tilde" function-key sequences (`ESC [ n [;mod] ~`).
///
/// Before the fix the escape-sequence parser assumed every `ESC[` sequence was
/// three bytes, so a four-byte tilde key (Delete = `ESC[3~`, PageUp = `ESC[5~`,
/// …) emitted a spurious `Escape` — which could dismiss a modal or pop
/// navigation — and left the trailing `~` to be inserted into focused text.
@MainActor
@Suite
struct VT220FunctionKeyParserTests {
  // MARK: - Keys without a KeyEvent case are consumed, not corrupted

  @Test(
    "Tilde keys without a KeyEvent case emit no event (no Escape, no '~')",
    arguments: [
      "\u{1B}[2~",  // Insert
      "\u{1B}[3~",  // Delete (forward)
      "\u{1B}[5~",  // PageUp
      "\u{1B}[6~",  // PageDown
      "\u{1B}[15~",  // F5 (multi-digit parameter)
      "\u{1B}[24~",  // F12
    ]
  )
  func unmappedTildeKeysAreConsumed(sequence: String) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events.isEmpty)
  }

  @Test("Modified tilde key (Ctrl+Delete = ESC[3;5~) is consumed without an event")
  func modifiedDeleteIsConsumed() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[3;5~".utf8))
    #expect(events.isEmpty)
  }

  // MARK: - The actual bug: no stray Escape, no literal tilde injection

  @Test("Delete does not inject a literal '~' into following text")
  func deleteFollowedByCharacterDoesNotInjectTilde() {
    var parser = TerminalInputParser()
    // Regression: previously yielded [.escape, .character("~"), .character("a")].
    let events = parser.feed(Array("\u{1B}[3~a".utf8))
    #expect(events == [.key(KeyPress(.character("a")))])
  }

  @Test("PageUp does not emit a modal-dismissing Escape")
  func pageUpDoesNotEmitEscape() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[5~".utf8))
    #expect(!events.contains(.key(KeyPress(.escape))))
    #expect(events.isEmpty)
  }

  // MARK: - VT220 forms of Home/End map to their KeyEvent cases

  @Test(
    "VT220 Home (ESC[1~ / ESC[7~) maps to .home",
    arguments: ["\u{1B}[1~", "\u{1B}[7~"]
  )
  func vt220HomeMapsToHome(sequence: String) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(.home))])
  }

  @Test(
    "VT220 End (ESC[4~ / ESC[8~) maps to .end",
    arguments: ["\u{1B}[4~", "\u{1B}[8~"]
  )
  func vt220EndMapsToEnd(sequence: String) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(.end))])
  }

  // MARK: - Incremental arrival

  @Test("A tilde sequence split across feeds is buffered, not mis-parsed")
  func splitTildeSequenceIsBuffered() {
    var parser = TerminalInputParser()
    let firstHalf = parser.feed(Array("\u{1B}[3".utf8))
    #expect(firstHalf.isEmpty)  // must wait, not emit an Escape

    let secondHalf = parser.feed(Array("~a".utf8))
    #expect(secondHalf == [.key(KeyPress(.character("a")))])
  }

  // MARK: - Regressions: existing sequences keep working

  @Test("Plain arrow keys still parse after the tilde change")
  func plainArrowsStillWork() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[A".utf8))
    #expect(events == [.key(KeyPress(.arrowUp))])
  }

  @Test("Modifier letter form (Ctrl+Up = ESC[1;5A) still parses")
  func modifierLetterFormStillWorks() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[1;5A".utf8))
    #expect(events == [.key(KeyPress(.arrowUp, modifiers: .ctrl))])
  }

  @Test("Bracketed paste (ESC[200~ … ESC[201~) is unaffected by tilde handling")
  func bracketedPasteStillWorks() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[200~hello\u{1B}[201~".utf8))
    #expect(events == [.paste(PasteEvent(content: "hello"))])
  }
}
