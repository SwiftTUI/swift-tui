import Testing

@testable import SwiftTUIRuntime

@Suite
struct TerminalParserRecoveryTests {
  @Test(
    "SS3 keys and unknown finals are invariant under every byte split",
    arguments: Array("PQRSABCDHFMz".utf8))
  func ss3Splits(final: UInt8) {
    let bytes: [UInt8] = [0x1B, 0x4F, final, 0x71]
    var whole = TerminalInputParser()
    let expected = whole.feed(bytes)
    for split in 0...bytes.count {
      var parser = TerminalInputParser()
      let actual =
        parser.feed(Array(bytes.prefix(split))) + parser.feed(Array(bytes.dropFirst(split)))
      #expect(actual == expected)
      #expect(parser.flush().isEmpty)
      #expect(parser.feed([0x72]) == [.key(.character("r"))])
    }
  }

  @Test("C1 OSC and seven-bit OSC recover at idle without leaking their payload")
  func controlStringRecovery() {
    for prefix: [UInt8] in [[0x9D], [0x1B, 0x5D]] {
      var parser = TerminalInputParser()
      #expect(parser.feed(prefix + [0x78]).isEmpty)
      #expect(parser.isAwaitingEscapeDisambiguation)
      #expect(parser.flush().isEmpty)
      #expect(!parser.isAwaitingEscapeDisambiguation)
      #expect(parser.feed([0x71]) == [.key(.character("q"))])
      for terminator: [UInt8] in [[0x07], [0x9C], [0x1B, 0x5C]] {
        let bytes = prefix + [0x78] + terminator + [0x71]
        for split in 0...bytes.count {
          var complete = TerminalInputParser()
          let events =
            complete.feed(Array(bytes.prefix(split)))
            + complete.feed(Array(bytes.dropFirst(split)))
          #expect(events == [.key(.character("q"))])
        }
      }
    }
    var bare = TerminalInputParser()
    #expect(bare.feed([0x9D]).isEmpty)
    #expect(bare.flush().isEmpty)
    #expect(bare.feed([0x71]) == [.key(.character("q"))])
  }

  @Test(
    "ignored input drains iteratively without losing following keys",
    arguments: [
      [UInt8](arrayLiteral: 0x80), [0], Array("\u{1B}Oz".utf8),
      Array("\u{1B}[9~".utf8), Array("\u{1B}[?1c".utf8),
      Array("\u{1B}[<128;1;1M".utf8), [0xC0, 0xAF],
    ])
  func ignoredFlood(envelope: [UInt8]) {
    var parser = TerminalInputParser()
    let bytes: [UInt8] = Array(repeating: envelope, count: 20_000).flatMap { $0 } + [UInt8(0x71)]
    #expect(parser.feed(bytes) == [.key(.character("q"))])
  }
}
