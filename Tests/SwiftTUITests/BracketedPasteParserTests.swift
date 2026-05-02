import Testing

@testable import SwiftTUI

@Suite
struct BracketedPasteParserTests {
  @Test("A complete bracketed-paste envelope emits a single PasteEvent")
  func completeEnvelope() {
    var parser = TerminalInputParser()
    let bytes = Array("\u{1B}[200~/Users/me/file.txt\u{1B}[201~".utf8)
    let events = parser.feed(bytes)
    #expect(events == [.paste(PasteEvent(content: "/Users/me/file.txt"))])
  }

  @Test("An unterminated envelope yields no events and preserves bytes for more input")
  func unterminatedEnvelope() {
    var parser = TerminalInputParser()
    let first = parser.feed(Array("\u{1B}[200~/Users/me/fil".utf8))
    #expect(first.isEmpty)
    let second = parser.feed(Array("e.txt\u{1B}[201~".utf8))
    #expect(second == [.paste(PasteEvent(content: "/Users/me/file.txt"))])
  }

  @Test("Paste envelopes tolerate embedded newlines")
  func embeddedNewlines() {
    var parser = TerminalInputParser()
    let bytes = Array("\u{1B}[200~/a\n/b\u{1B}[201~".utf8)
    let events = parser.feed(bytes)
    #expect(events == [.paste(PasteEvent(content: "/a\n/b"))])
  }

  @Test("Non-paste escape sequences are unaffected")
  func nonPasteEscape() {
    var parser = TerminalInputParser()
    // A bare ESC-key press
    let events = parser.feed([0x1B])
    #expect(events.count == 1)
    if case .key(let keyPress) = events[0] {
      #expect(keyPress.key == .escape)
    } else {
      Issue.record("expected .key(.escape)")
    }
  }
}
