import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Regression coverage for the unbounded-numeric-parameter overflow.
///
/// CSI/SGR/VT220 numeric parameters used to accumulate through checked
/// `value * 10 + digit` arithmetic, so an absurdly long (malformed or
/// adversarial) parameter overflowed `Int` and trapped the process — a
/// deterministic denial of service reachable on any input path, including the
/// remote WebHost forwarder, and worse on wasm32 where `Int` is 32-bit. The
/// parser must instead drop the malformed sequence and keep parsing.
///
/// All three numeric entry points funnel through `asciiInteger`, so each case
/// exercises a different caller: SGR mouse coordinates, CSI modifier params,
/// and VT220 tilde key-ids.
@MainActor
@Suite
struct InputParserOverflowTests {
  /// 40 digits overflows both 64-bit and 32-bit `Int`.
  private let overlong = String(repeating: "9", count: 40)

  @Test("Overlong SGR mouse coordinate is dropped, not trapped, and parsing recovers")
  func overlongSGRCoordinateRecovers() {
    var parser = TerminalInputParser()

    // The overflowing envelope is consumed but yields no event (a consumed-but-
    // empty sequence ends the current drain). The crucial property is that it
    // does not trap and the buffer is not wedged: a subsequent valid sequence
    // still parses on the next feed, exactly as bytes arrive over a stream.
    let dropped = parser.feed(Array("\u{001B}[<0;\(overlong);7M".utf8))
    #expect(dropped == [])

    let recovered = parser.feed(Array("\u{001B}[<0;5;7M".utf8))
    #expect(
      recovered == [
        .mouse(
          MouseEvent(
            kind: .down(.primary),
            location: .cellFallback(CellPoint(x: 4, y: 6))
          )
        )
      ])
  }

  @Test("Overlong CSI modifier parameter degrades to no modifiers, not a trap")
  func overlongCSIModifierDegrades() {
    var parser = TerminalInputParser()

    // ESC [ 1 ; <overflow> A — the modifier group overflows; csiModifiers must
    // treat the unparsable value as "no modifiers" and still emit the key.
    let events = parser.feed(Array("\u{001B}[1;\(overlong)A".utf8))
    #expect(events == [.key(KeyPress(.arrowUp))])
  }

  @Test("Overlong VT220 tilde key-id is dropped, not trapped, and parsing recovers")
  func overlongTildeKeyIDRecovers() {
    var parser = TerminalInputParser()

    // ESC [ <overflow> ~ followed by a plain 'q': the tilde envelope is
    // consumed (key-id unparsable -> dropped) and the trailing key still parses.
    let bytes = Array("\u{001B}[\(overlong)~".utf8) + [0x71]
    let events = parser.feed(bytes)
    #expect(events == [.key(KeyPress(.character("q")))])
  }

  @Test("Large but representable coordinate still parses unchanged")
  func largeRepresentableCoordinateParses() {
    var parser = TerminalInputParser()

    // Guards against an over-eager bound: a big yet representable value must not
    // be dropped. SGR coordinates are 1-based, so 500;7 maps to cell (499, 6).
    let events = parser.feed(Array("\u{001B}[<0;500;7M".utf8))
    #expect(
      events == [
        .mouse(
          MouseEvent(
            kind: .down(.primary),
            location: .cellFallback(CellPoint(x: 499, y: 6))
          )
        )
      ])
  }
}
