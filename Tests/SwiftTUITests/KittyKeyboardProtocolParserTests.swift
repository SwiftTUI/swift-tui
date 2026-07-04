import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Coverage for kitty keyboard protocol envelopes (`ESC [ <params> u`),
/// parsed unconditionally by ``TerminalInputParser`` (F14 stage 2).
///
/// The protocol's flag 1 (disambiguate escape codes) re-encodes exactly the
/// keys whose legacy byte forms are ambiguous: the bare ESC key, ctrl+letter
/// combinations that collide with control characters (ctrl+j = LF = Enter,
/// ctrl+i = Tab), and alt+letter's ESC prefix. Keys with unambiguous legacy
/// encodings (arrows, tilde keys, F1–F12) keep those encodings even in
/// enhanced mode, so the stage-1 paths stay load-bearing alongside this one.
@MainActor
@Suite
struct KittyKeyboardProtocolParserTests {
  // MARK: - The ctrl+j collision (the fix this stage exists for)

  @Test("Ctrl+J arrives as its own key, distinct from Enter")
  func ctrlJIsDistinctFromEnter() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[106;5u".utf8))
    #expect(events == [.key(KeyPress(.character("j"), modifiers: .ctrl))])
  }

  @Test("Legacy linefeed still maps to Enter for non-enhanced terminals")
  func legacyLinefeedRemainsEnter() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x0A])
    #expect(events == [.key(KeyPress(.return))])
  }

  @Test("Ctrl+I arrives as its own key, distinct from Tab")
  func ctrlIIsDistinctFromTab() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[105;5u".utf8))
    #expect(events == [.key(KeyPress(.character("i"), modifiers: .ctrl))])
  }

  // MARK: - Disambiguated core keys

  @Test("CSI 27u delivers the Escape key")
  func escapeCodePointDelivers() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[27u".utf8))
    #expect(events == [.key(KeyPress(.escape))])
  }

  @Test(
    "Modified control keys map through with their modifiers",
    arguments: [
      ("\u{1B}[13;2u", KeyEvent.return, EventModifiers.shift),
      ("\u{1B}[9;5u", KeyEvent.tab, EventModifiers.ctrl),
      ("\u{1B}[32;5u", KeyEvent.space, EventModifiers.ctrl),
      ("\u{1B}[127;3u", KeyEvent.backspace, EventModifiers.alt),
      ("\u{1B}[106;6u", KeyEvent.character("j"), EventModifiers([.ctrl, .shift])),
      ("\u{1B}[111;3u", KeyEvent.character("o"), EventModifiers.alt),
    ] as [(String, KeyEvent, EventModifiers)]
  )
  func modifiedKeysMapThrough(
    sequence: String,
    key: KeyEvent,
    modifiers: EventModifiers
  ) {
    var parser = TerminalInputParser()
    let events = parser.feed(Array(sequence.utf8))
    #expect(events == [.key(KeyPress(key, modifiers: modifiers))])
  }

  // MARK: - Functional code points

  @Test("F-key code points map to functionKey cases")
  func functionKeyCodePointsMap() {
    var parser = TerminalInputParser()
    #expect(
      parser.feed(Array("\u{1B}[57364;2u".utf8))
        == [.key(KeyPress(.functionKey(1), modifiers: .shift))]
    )
    #expect(parser.feed(Array("\u{1B}[57387u".utf8)) == [.key(KeyPress(.functionKey(24)))])
  }

  @Test("Keypad Enter (57414) delivers Return")
  func keypadEnterDeliversReturn() {
    var parser = TerminalInputParser()
    let events = parser.feed(Array("\u{1B}[57414u".utf8))
    #expect(events == [.key(KeyPress(.return))])
  }

  @Test("Unmapped private-use functional codes are consumed without an event")
  func unmappedFunctionalCodesConsumeSilently() {
    var parser = TerminalInputParser()
    // KP_0 (57399) and CAPS_LOCK (57358) have no KeyEvent mapping. The
    // envelope must vanish whole — never an Escape plus literal text.
    let events = parser.feed(Array("\u{1B}[57399u\u{1B}[57358ua".utf8))
    #expect(events == [.key(KeyPress(.character("a")))])
  }

  // MARK: - Tolerated enhancement subparameters

  @Test("Alternate-key subparameters use the base code point")
  func alternateKeysUseBaseCodePoint() {
    var parser = TerminalInputParser()
    // code:shifted-code — sent only under flags this host never requests.
    let events = parser.feed(Array("\u{1B}[106:74;5u".utf8))
    #expect(events == [.key(KeyPress(.character("j"), modifiers: .ctrl))])
  }

  @Test("Press and repeat event types deliver; release is swallowed")
  func eventTypesFilterReleases() {
    var parser = TerminalInputParser()
    #expect(
      parser.feed(Array("\u{1B}[106;5:1u".utf8))
        == [.key(KeyPress(.character("j"), modifiers: .ctrl))]
    )
    #expect(
      parser.feed(Array("\u{1B}[106;5:2u".utf8))
        == [.key(KeyPress(.character("j"), modifiers: .ctrl))]
    )
    // A release must not double-fire, and must not strand following input.
    #expect(
      parser.feed(Array("\u{1B}[106;5:3ua".utf8))
        == [.key(KeyPress(.character("a")))]
    )
  }

  @Test("Lock-state modifier bits are dropped; the key still delivers")
  func lockStateBitsAreDropped() {
    var parser = TerminalInputParser()
    // 69 = 1 + ctrl(4) + caps_lock(64).
    let events = parser.feed(Array("\u{1B}[106;69u".utf8))
    #expect(events == [.key(KeyPress(.character("j"), modifiers: .ctrl))])
  }

  @Test("Unrepresentable modifiers (super/hyper/meta) swallow the event")
  func unrepresentableModifiersSwallowEvent() {
    var parser = TerminalInputParser()
    // 9 = 1 + super(8). Delivering super+j as plain "j" would type text
    // the user never intended; the envelope is consumed silently.
    let events = parser.feed(Array("\u{1B}[106;9ua".utf8))
    #expect(events == [.key(KeyPress(.character("a")))])
  }

  // MARK: - Robustness

  @Test("Split-fed envelopes buffer until the terminator arrives")
  func splitFeedBuffers() {
    var parser = TerminalInputParser()
    #expect(parser.feed(Array("\u{1B}[106;5".utf8)).isEmpty)
    #expect(parser.feed(Array("u".utf8)) == [.key(KeyPress(.character("j"), modifiers: .ctrl))])
  }

  @Test("Malformed envelopes are consumed without corrupting following input")
  func malformedEnvelopesConsumeSilently() {
    var parser = TerminalInputParser()
    // An unmappable control code point (5) and an empty modifier section:
    // the envelope must vanish whole, never leaking parameter text.
    let events = parser.feed(Array("\u{1B}[5;ua".utf8))
    #expect(events == [.key(KeyPress(.character("a")))])
  }

  @Test("Legacy modified CSI keys still parse (no regression from the u-branch)")
  func legacyModifiedCSIKeysUnaffected() {
    var parser = TerminalInputParser()
    #expect(
      parser.feed(Array("\u{1B}[1;5P".utf8))
        == [.key(KeyPress(.functionKey(1), modifiers: .ctrl))]
    )
    #expect(
      parser.feed(Array("\u{1B}[3;5~".utf8))
        == [.key(KeyPress(.delete, modifiers: .ctrl))]
    )
  }
}
