import Testing

@testable import SwiftTUIRuntime

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

  @Test("A bare ESC stays buffered until an idle flush commits it to Escape")
  func nonPasteEscape() {
    var parser = TerminalInputParser()
    // A bare ESC is byte-identical to the first byte of every escape sequence
    // (arrows, function keys, bracketed paste), so byte-wise the parser cannot
    // yet tell an Escape keypress from the start of a longer sequence. It keeps
    // the ESC buffered; the run loop's idle escape-timeout resolves it out of
    // band via `flush()` (the vim `ttimeoutlen` model).
    #expect(parser.feed([0x1B]).isEmpty)
    #expect(parser.isAwaitingEscapeDisambiguation)
    #expect(parser.flush() == [.key(KeyPress(.escape))])
    #expect(!parser.isAwaitingEscapeDisambiguation)
    // Flushing again with nothing pending yields nothing.
    #expect(parser.flush().isEmpty)
  }
}
