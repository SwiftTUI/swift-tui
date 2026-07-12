import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressTerminalAppearanceQueryTests {
  @Test("stress terminal appearance query 001 foreground selection ignores leading probe noise")
  func appearanceQuery001ForegroundSelectionIgnoresLeadingProbeNoise() {
    // Hypothesis: an unrelated reply before the requested OSC can shift prefix selection.
    let bytes = Array("noise\u{001B}]11;rgb:0/0/0\u{0007}\u{001B}]10;rgb:f/8/0\u{0007}".utf8)

    #expect(TerminalAppearanceQuery.foreground.extractResponse(from: bytes) == "rgb:f/8/0")
  }

  @Test("stress terminal appearance query 002 string terminator closes the selected reply")
  func appearanceQuery002StringTerminatorClosesSelectedReply() {
    // Hypothesis: the ST path can accidentally retain its ESC byte in the color payload.
    let bytes = Array("\u{001B}]4;4;rgb:12/34/56\u{001B}\\trailing".utf8)

    #expect(
      TerminalAppearanceQuery.palette(index: 4).extractResponse(from: bytes) == "rgb:12/34/56")
  }

  @Test("stress terminal appearance query 003 unterminated replies remain incomplete")
  func appearanceQuery003UnterminatedRepliesRemainIncomplete() {
    // Hypothesis: a partial read can be mistaken for a complete appearance response.
    let bytes = Array("\u{001B}]10;rgb:ffff/ffff/ffff".utf8)

    #expect(TerminalAppearanceQuery.foreground.extractResponse(from: bytes) == nil)
  }

  @Test("stress terminal appearance query 004 adjacent OSC replies cannot cross terminate")
  func appearanceQuery004AdjacentOSCRepliesCannotCrossTerminate() {
    // Hypothesis: a missing terminator on the selected reply can borrow the next reply's BEL.
    let bytes = Array("\u{001B}]10;rgb:f/f/f\u{001B}]11;rgb:0/0/0\u{0007}".utf8)

    #expect(TerminalAppearanceQuery.foreground.extractResponse(from: bytes) == nil)
  }

  @Test("stress terminal appearance query 005 one digit RGB components normalize independently")
  func appearanceQuery005OneDigitRGBComponentsNormalizeIndependently() throws {
    // Hypothesis: short xterm RGB components can be normalized as byte-width components.
    let color = try #require(TerminalAppearanceQuery.foreground.parseColor(from: "rgb:f/8/0"))

    #expect(color.red == 1)
    #expect(color.green == 8.0 / 15.0)
    #expect(color.blue == 0)
  }

  @Test("stress terminal appearance query 006 four digit RGB components preserve precision")
  func appearanceQuery006FourDigitRGBComponentsPreservePrecision() throws {
    // Hypothesis: 16-bit terminal replies can be truncated through an 8-bit assumption.
    let color = try #require(
      TerminalAppearanceQuery.background.parseColor(from: "rgb:ffff/8000/0001")
    )

    #expect(color.red == 1)
    #expect(color.green == 32768.0 / 65535.0)
    #expect(color.blue == 1.0 / 65535.0)
  }

  @Test("stress terminal appearance query 007 surrounding whitespace does not poison hex color")
  func appearanceQuery007SurroundingWhitespaceDoesNotPoisonHexColor() throws {
    // Hypothesis: terminals padding an OSC response can bypass otherwise valid hex parsing.
    let color = try #require(
      TerminalAppearanceQuery.palette(index: 4).parseColor(from: " \t#123456\n")
    )

    #expect(color == Color(red: 0x12 / 255.0, green: 0x34 / 255.0, blue: 0x56 / 255.0))
  }

  @Test("stress terminal appearance query 008 missing RGB components are rejected")
  func appearanceQuery008MissingRGBComponentsAreRejected() {
    // Hypothesis: separator compaction can reinterpret a missing channel as a shorter color.
    #expect(TerminalAppearanceQuery.foreground.parseColor(from: "rgb:ffff//0000") == nil)
  }

  @Test("stress terminal appearance query 009 signed RGB components are rejected")
  func appearanceQuery009SignedRGBComponentsAreRejected() {
    // Hypothesis: radix parsing can admit negative channel values into terminal appearance state.
    #expect(TerminalAppearanceQuery.foreground.parseColor(from: "rgb:-1/0/0") == nil)
  }
}
