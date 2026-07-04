import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Coverage for VT220 "tilde" function-key sequences (`ESC [ n [;mod] ~`) and
/// xterm SS3 sequences (`ESC O <final>`).
///
/// History: the escape-sequence parser originally assumed every `ESC[`
/// sequence was three bytes, so a four-byte tilde key emitted a spurious
/// `Escape` — which could dismiss a modal or pop navigation — and left the
/// trailing `~` to be inserted into focused text. The first fix consumed the
/// envelopes but dropped the keys (no `KeyEvent` cases existed); F14 stage 1
/// added the cases, so these keys now deliver. SS3 had the same corruption
/// shape: `ESC O P` (xterm F1) parsed as Alt+O plus a literal `P` injected
/// into the focused field.
@MainActor
@Suite
struct VT220FunctionKeyParserTests {
  // MARK: - Tilde keys deliver their KeyEvents (F14 stage 1)

  @Test(
    "Tilde keys map to their KeyEvent cases",
    arguments: [
      ("\u{1B}[2~", KeyEvent.insert),
      ("\u{1B}[3~", KeyEvent.delete),
      ("\u{1B}[5~", KeyEvent.pageUp),
      ("\u{1B}[6~", KeyEvent.pageDown),
      ("\u{1B}[11~", KeyEvent.functionKey(1)),
      ("\u{1B}[15~", KeyEvent.functionKey(5)),
      ("\u{1B}[17~", KeyEvent.functionKey(6)),
      ("\u{1B}[21~", KeyEvent.functionKey(10)),
      ("\u{1B}[23~", KeyEvent.functionKey(11)),
      ("\u{1B}[24~", KeyEvent.functionKey(12)),
      ("\u{1B}[26~", KeyEvent.functionKey(14)),
      ("\u{1B}[29~", KeyEvent.functionKey(16)),
      ("\u{1B}[34~", KeyEvent.functionKey(20)),
    ]
  )
  func tildeKeysDeliver(sequence: String, key: KeyEvent) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(key))])
  }

  @Test("Modified tilde key (Ctrl+Delete = ESC[3;5~) carries its modifiers")
  func modifiedDeleteCarriesModifiers() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[3;5~".utf8))
    #expect(events == [.key(KeyPress(.delete, modifiers: .ctrl))])
  }

  @Test("Unassigned VT220 slots (ESC[16~) are consumed without an event")
  func unassignedTildeSlotIsConsumed() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[16~".utf8))
    #expect(events.isEmpty)
  }

  // MARK: - The original bug shape: no stray Escape, no literal tilde injection

  @Test("Delete does not inject a literal '~' into following text")
  func deleteFollowedByCharacterDoesNotInjectTilde() {
    var parser = TerminalInputParser()
    // Regression: previously yielded [.escape, .character("~"), .character("a")].
    let events = parser.feed(Array("\u{1B}[3~a".utf8))
    #expect(events == [.key(KeyPress(.delete)), .key(KeyPress(.character("a")))])
  }

  @Test("PageUp does not emit a modal-dismissing Escape")
  func pageUpDoesNotEmitEscape() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[5~".utf8))
    #expect(!events.contains(.key(KeyPress(.escape))))
    #expect(events == [.key(KeyPress(.pageUp))])
  }

  // MARK: - SS3 sequences (ESC O <final>)

  @Test(
    "SS3 F1–F4 deliver function keys",
    arguments: [
      ("\u{1B}OP", 1), ("\u{1B}OQ", 2), ("\u{1B}OR", 3), ("\u{1B}OS", 4),
    ]
  )
  func ss3FunctionKeysDeliver(sequence: String, number: Int) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(.functionKey(number)))])
  }

  @Test("SS3 F1 does not corrupt focused text (no Alt+O, no literal 'P')")
  func ss3DoesNotInjectLiteralFinal() {
    var parser = TerminalInputParser()
    // Regression: previously yielded [.key(alt+O), .key(.character("P")), …].
    let events = parser.feed(Array("\u{1B}OPa".utf8))
    #expect(events == [.key(KeyPress(.functionKey(1))), .key(KeyPress(.character("a")))])
  }

  @Test(
    "SS3 application-cursor aliases map to their keys",
    arguments: [
      ("\u{1B}OA", KeyEvent.arrowUp),
      ("\u{1B}OB", KeyEvent.arrowDown),
      ("\u{1B}OC", KeyEvent.arrowRight),
      ("\u{1B}OD", KeyEvent.arrowLeft),
      ("\u{1B}OH", KeyEvent.home),
      ("\u{1B}OF", KeyEvent.end),
      ("\u{1B}OM", KeyEvent.return),
    ]
  )
  func ss3AliasesDeliver(sequence: String, key: KeyEvent) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(key))])
  }

  @Test("Unknown SS3 final is consumed whole, never inserted as text")
  func unknownSS3FinalIsConsumed() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}Oza".utf8))
    #expect(events == [.key(KeyPress(.character("a")))])
  }

  @Test("A chunk ending at ESC O is Alt+O (chunk boundary as ESC timeout)")
  func chunkEndingAtEscOIsAltO() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}O".utf8))
    #expect(events == [.key(KeyPress(.character("O"), modifiers: .alt))])
  }

  // MARK: - Modified CSI forms

  @Test("Modified F1 (ESC[1;5P) parses as Ctrl+F1")
  func modifiedCSIFunctionKeyParses() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[1;5P".utf8))
    #expect(events == [.key(KeyPress(.functionKey(1), modifiers: .ctrl))])
  }

  @Test("Shift+PageUp (ESC[5;2~) carries the shift modifier")
  func shiftPageUpParses() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[5;2~".utf8))
    #expect(events == [.key(KeyPress(.pageUp, modifiers: .shift))])
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
    #expect(secondHalf == [.key(KeyPress(.delete)), .key(KeyPress(.character("a")))])
  }

  // MARK: - Regressions: existing sequences keep working

  @Test("Plain arrow keys still parse after the tilde change")
  func plainArrowsStillWork() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[A".utf8))
    #expect(events == [.key(KeyPress(.arrowUp))])
  }

  @Test("Alt+letter (including lowercase o) still parses")
  func altLetterStillWorks() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}o".utf8))
    #expect(events == [.key(KeyPress(.character("o"), modifiers: .alt))])
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
