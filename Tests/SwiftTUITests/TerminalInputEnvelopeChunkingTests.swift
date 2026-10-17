import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@Suite struct TerminalInputEnvelopeChunkingTests {
  @Test func everyByteSplitPreservesCompleteEnvelopeMeaning() {
    let cases: [([UInt8], [InputEvent])] = [
      (Array("\u{1B}[27;5;13~".utf8), [.key(.init(.return, modifiers: .ctrl))]),
      (Array("\u{1B}é".utf8), [.key(.init(.character("é"), modifiers: .alt))]),
      (Array("\u{1B}😀".utf8), [.key(.init(.character("😀"), modifiers: .alt))]),
      (Array("\u{FFFD}".utf8), [.key(.init(.character("\u{FFFD}")))]),
      ([0x9B, 0x31, 0x3B, 0x35, 0x41], [.key(.init(.arrowUp, modifiers: .ctrl))]),
      ([0x1B, 0x5B, 0x4D, 0x20, 0x21, 0x21], []),
      (
        [0x9B, 0x32, 0x30, 0x30, 0x7E, 0x61, 0x9B, 0x32, 0x30, 0x31, 0x7E],
        [.paste(.init(content: "a"))]
      ),
      (Array("\u{1B}[1;999999999999999999999999A".utf8), []),
    ]
    for (bytes, expected) in cases {
      for split in 0...bytes.count {
        var parser = TerminalInputParser()
        let first = parser.feed(Array(bytes[..<split]))
        let second = parser.feed(Array(bytes[split...]))
        #expect(first + second == expected, "bytes=\(bytes), split=\(split)")
        #expect(parser.flush().isEmpty)
        #expect(parser.feed([0x78]) == [.key(.init(.character("x")))])
      }
    }
  }

  @Test func explicitRecoveryKeepsControlPayloadsOutOfTyping() {
    for bytes: [UInt8] in [[0x9B], [0x9B, 0x31, 0x3B], [0x1B, 0x5B, 0x4D, 0x20]] {
      var parser = TerminalInputParser()
      #expect(parser.feed(bytes).isEmpty)
      #expect(parser.isAwaitingEscapeDisambiguation)
      #expect(parser.flush().isEmpty)
      #expect(parser.feed([0x61]) == [.key(.init(.character("a")))])
    }
  }
}
