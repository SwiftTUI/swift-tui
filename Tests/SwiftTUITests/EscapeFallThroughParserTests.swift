import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// F165: Escape must not leak from Alt+control chords or failed CSI parses.
/// Escape is framework-reserved for dismiss, so a stray `.escape` plus a
/// re-parsed literal (`ESC 0x0D` → `.escape` + `.return`) closes a sheet AND
/// activates what's underneath in one keystroke.
@MainActor
@Suite
struct EscapeFallThroughParserTests {
  // MARK: - Alt+control chords (ESC + C0 byte)

  @Test("Alt+Return emits return with the alt modifier, never Escape plus Return")
  func altReturn() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x0D])
    #expect(events == [.key(KeyPress(.return, modifiers: .alt))])
  }

  @Test("Alt+Return via linefeed emits return with the alt modifier")
  func altReturnLinefeed() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x0A])
    #expect(events == [.key(KeyPress(.return, modifiers: .alt))])
  }

  @Test("Alt+Backspace emits backspace with the alt modifier, never Escape plus Backspace")
  func altBackspace() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x7F])
    #expect(events == [.key(KeyPress(.backspace, modifiers: .alt))])
  }

  @Test("Alt+Ctrl+H emits backspace with the alt modifier")
  func altCtrlH() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x08])
    #expect(events == [.key(KeyPress(.backspace, modifiers: .alt))])
  }

  @Test("Alt+Tab emits tab with the alt modifier")
  func altTab() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x09])
    #expect(events == [.key(KeyPress(.tab, modifiers: .alt))])
  }

  @Test("Alt+Ctrl+letter emits the letter with both modifiers")
  func altCtrlLetter() {
    var parser = TerminalInputParser()
    let events = parser.feed([0x1B, 0x01])
    #expect(events == [.key(KeyPress(.character("a"), modifiers: [.ctrl, .alt]))])
  }

  // MARK: - Failed CSI modifier parses

  @Test("a short parameterized CSI that is not a modifier form discards silently")
  func shortNonModifierCSIDiscards() {
    var parser = TerminalInputParser()
    // ESC [ 1 A — a parameterized cursor sequence this parser does not map.
    // The old fall-through consumed three bytes, emitted a modal-dismissing
    // Escape, and re-parsed 'A' as literal text.
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x41])
    #expect(events.isEmpty, "unmapped CSI must be ignored whole; got \(events)")
  }

  @Test("a multi-digit non-modifier CSI envelope discards silently")
  func multiDigitNonModifierCSIDiscards() {
    var parser = TerminalInputParser()
    // ESC [ 1 2 X — the old fall-through stranded '2X' as literal text.
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x32, 0x58])
    #expect(events.isEmpty, "unmapped CSI must be ignored whole; got \(events)")
  }

  @Test("a failed CSI parse does not swallow a following keystroke")
  func failedCSIDoesNotSwallowFollowingKey() {
    var parser = TerminalInputParser()
    // The discarded envelope must consume exactly itself: a following 'x'
    // in the same chunk still types.
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x41, 0x78])
    #expect(events == [.key(KeyPress(.character("x")))])
  }

  @Test("a real modifier sequence still parses after the fall-through change")
  func realModifierSequenceStillParses() {
    var parser = TerminalInputParser()
    // ESC [ 1 ; 5 A = Ctrl+ArrowUp.
    let events = parser.feed([0x1B, 0x5B, 0x31, 0x3B, 0x35, 0x41])
    #expect(events == [.key(KeyPress(.arrowUp, modifiers: .ctrl))])
  }
}
