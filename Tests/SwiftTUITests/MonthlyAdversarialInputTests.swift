import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// September–October 2026 audit: STUI-510, STUI-607, STUI-700, STUI-826,
// STUI-892, STUI-893 and STUI-949. Each envelope must recover independently
// of transport chunking; expected events are specified independently of the parser.
@Suite("Monthly adversarial terminal input")
struct MonthlyAdversarialInputTests {
  @Test func audit001OSCWithEmbeddedEscape() {
    partitions("\u{1B}]11;rgb:aa\u{1B}X/bb/cc\u{1B}\\q", [.key(.init(.character("q")))])
  }

  @Test func audit002DCSDoesNotEndAtBEL() {
    partitions("\u{1B}Ppayload\u{7}still-payload\u{1B}\\q", [.key(.init(.character("q")))])
  }

  @Test func audit003APCWithFalseTerminator() {
    partitions("\u{1B}_Gid=2;\u{1B}/OK\u{1B}\\q", [.key(.init(.character("q")))])
  }

  @Test func audit004PMWithEightBitTerminator() {
    partitions(Array("\u{1B}^private".utf8) + [0x9C, 0x71], [.key(.init(.character("q")))])
  }

  @Test func audit005EightBitOSCWithBEL() {
    partitions([0x9D] + Array("11;rgb:aa/bb/cc".utf8) + [7, 0x71], [.key(.init(.character("q")))])
  }

  @Test func audit006UnknownEnvelopesBetweenKeys() {
    partitions(
      "a\u{1B}[99~\u{1B}OZ\u{1B}[?999;1$yb",
      [
        .key(.init(.character("a"))), .key(.init(.character("b"))),
      ])
  }

  @Test func audit007KittyReleaseCannotConsumeFollowingArrow() {
    partitions(
      "\u{1B}[97;1:3u\u{1B}[Dq",
      [
        .key(.init(.arrowLeft)), .key(.init(.character("q"))),
      ])
  }

  @Test func audit008OverflowEnvelopesDrainInOneRead() {
    let huge = String(repeating: "9", count: 40)
    partitions(
      "\u{1B}[\(huge)~\u{1B}[<0;\(huge);2M\u{1B}[\(huge)uq",
      [
        .key(.init(.character("q")))
      ])
  }

  @Test func audit009BrokenUTF8CannotEatASCII() {
    partitions([0xF0, 0x41, 0x42, 0x43, 0x44], "ABCD".map { .key(.init(.character($0))) })
  }

  @Test func audit010SurrogateUTF8RecoversBeforeValidEmoji() {
    partitions(
      [0xED, 0xA0, 0x80] + Array("😀q".utf8),
      [
        .key(.init(.character("😀"))), .key(.init(.character("q"))),
      ])
  }

  @Test func audit011OverlongUTF8CannotBecomeEscape() {
    partitions([0xE0, 0x80, 0x9B] + Array("q".utf8), [.key(.init(.character("q")))])
  }

  @Test func audit012AboveUnicodeMaximumRecovers() {
    partitions(
      [0xF4, 0x90, 0x80, 0x80] + Array("界q".utf8),
      [
        .key(.init(.character("界"))), .key(.init(.character("q"))),
      ])
  }

  @Test func audit013MousePressReleaseAndTextRemainOrdered() {
    let location = PointerLocation.cellFallback(CellPoint(x: 3, y: 6))
    partitions(
      "\u{1B}[<0;4;7M\u{1B}[<0;4;7mq",
      [
        .mouse(.init(kind: .down(.primary), location: location)),
        .mouse(.init(kind: .up(.primary), location: location)),
        .key(.init(.character("q"))),
      ])
  }

  @Test func audit014PasteContainsLiteralControlEnvelopes() {
    let payload = "before\u{1B}[A\u{1B}]11;x\u{7}after"
    partitions(
      "\u{1B}[200~\(payload)\u{1B}[201~q",
      [
        .paste(.init(content: payload)), .key(.init(.character("q"))),
      ])
  }

  @Test func audit015PasteFalseEndPrefixIsPreserved() {
    let payload = "a\u{1B}[20\u{1B}[201xb"
    partitions(
      "\u{1B}[200~\(payload)\u{1B}[201~q",
      [
        .paste(.init(content: payload)), .key(.init(.character("q"))),
      ])
  }

  @Test func audit016AdjacentPastesDoNotSharePayload() {
    partitions(
      "\u{1B}[200~first\u{1B}[201~\u{1B}[200~👩🏽‍💻\r\nlast\u{1B}[201~",
      [
        .paste(.init(content: "first")), .paste(.init(content: "👩🏽‍💻\r\nlast")),
      ])
  }

  @Test func audit017PrivateCSIAndNULCannotStrandText() {
    partitions("\u{0}\u{1B}[?1004;2$y\u{0}q\u{1B}[?1;2c", [.key(.init(.character("q")))])
  }

  @Test func audit018TruncatedControlStringFlushResetsParser() {
    for prefix in [
      "\u{1B}]unfinished", "\u{1B}Punfinished", "\u{1B}_unfinished", "\u{1B}^unfinished",
    ] {
      var parser = TerminalInputParser()
      #expect(parser.feed(Array(prefix.utf8)).isEmpty)
      #expect(parser.flush().isEmpty)
      #expect(parser.flush().isEmpty)
      #expect(
        parser.feed(Array("\u{1B}[Aq".utf8)) == [
          .key(.init(.arrowUp)), .key(.init(.character("q"))),
        ])
    }
  }

  @Test func audit019EscapeTimeoutDoesNotPoisonNextSequence() {
    var parser = TerminalInputParser()
    for _ in 0..<4 {
      #expect(parser.feed([0x1B]).isEmpty)
      #expect(parser.flush() == [.key(.init(.escape))])
      #expect(parser.flush().isEmpty)
      #expect(parser.feed(Array("\u{1B}OP".utf8)) == [.key(.init(.functionKey(1)))])
    }
  }

  @Test func audit020UnknownSS3BeforeMultibyteInput() {
    partitions("\u{1B}Ox界\u{1B}OQ", [.key(.init(.character("界"))), .key(.init(.functionKey(2)))])
  }

  private func partitions(_ text: String, _ expected: [InputEvent]) {
    partitions(Array(text.utf8), expected)
  }

  private func partitions(_ bytes: [UInt8], _ expected: [InputEvent]) {
    // Every single split plus byte-at-a-time delivery. No timeout is injected
    // between chunks: a read boundary is not an Escape disambiguation timeout.
    for split in 0...bytes.count {
      var parser = TerminalInputParser()
      var events = parser.feed(Array(bytes[..<split]))
      events += parser.feed(Array(bytes[split...]))
      events += parser.flush()
      #expect(events == expected, "split=\(split), bytes=\(bytes)")
      #expect(parser.feed([]).isEmpty)
    }
    var parser = TerminalInputParser()
    var events: [InputEvent] = []
    for byte in bytes { events += parser.feed([byte]) }
    events += parser.flush()
    #expect(events == expected, "byte-at-a-time, bytes=\(bytes)")
  }
}
