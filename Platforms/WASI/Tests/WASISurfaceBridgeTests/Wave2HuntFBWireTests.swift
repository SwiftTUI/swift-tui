// Wave-2 regression hunt, part FB (STUI-1165): the host-wire pointer grammar
// and its 2^24 bound (FW-E, ef4ce264; HOST-WIRE-CONTRACT.md) at the spelling
// classes and boundary values the repair's own tests did not list. Cases
// w2fb020-w2fb023; the brief and hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-2-hunt/fb/. Pure parser
// calls; no descriptors.
@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUIWASISurfaceBridge

@Suite("Wave-2 hunt FB: host-wire pointer grammar and bound")
struct Wave2HuntFBWireTests {
  private func pointerEvent(_ command: String) -> MouseEvent? {
    var parser = WebSurfaceInputParser()
    guard case .mouse(let event)? = parser.feed(Array("\u{1E}\(command)\n".utf8)).events.first
    else { return nil }
    return event
  }

  /// The three record forms for `kind`, coordinates `x`, `y` and deltas.
  private func forms(
    kind: String, x: String, y: String, deltaX: String = "0", deltaY: String = "0"
  ) -> [String] {
    let fields = "\(kind):\(x):\(y):none:\(deltaX):\(deltaY):0"
    return ["mouse:\(fields)", "mouseGeometry:3:\(fields)", "mouseViewport:3:4:\(fields)"]
  }

  @Test("w2fb020: coordinates of exactly 2^24 are accepted in every decimal spelling")
  func w2fb020WireCoordinatesAtTheBoundInEverySpelling() {
    let spellings: [(String, Double)] = [
      ("16777216", 16_777_216), ("+16777216", 16_777_216), ("-16777216", -16_777_216),
      ("16777216.0", 16_777_216), ("16777216.000", 16_777_216), ("1.6777216e7", 16_777_216),
      ("1.6777216E+7", 16_777_216), ("-1.6777216e+7", -16_777_216), ("167772.16e2", 16_777_216),
      ("0.16777216e8", 16_777_216), ("016777216", 16_777_216),
    ]
    for (spelling, value) in spellings {
      for command in forms(kind: "moved", x: spelling, y: "2") {
        #expect(pointerEvent(command)?.location.location == Point(x: value, y: 2), "\(command)")
      }
      for command in forms(kind: "moved", x: "2", y: spelling) {
        #expect(pointerEvent(command)?.location.location == Point(x: 2, y: value), "\(command)")
      }
    }
  }

  @Test("w2fb021: values just past 2^24 are refused in every decimal spelling")
  func w2fb021WireCoordinatesPastTheBoundInEverySpelling() {
    let spellings = [
      "16777217", "+16777217", "-16777217", "16777217.0", "1.6777217e7", "-1.6777217E+7",
      "16777216.000001", "1.67772161e7",
    ]
    for spelling in spellings {
      for command in forms(kind: "moved", x: spelling, y: "2")
        + forms(
          kind: "moved", x: "2", y: spelling)
      {
        #expect(pointerEvent(command) == nil, "\(command)")
      }
    }
    for delta in ["16777217", "-16777217"] {
      for command in forms(kind: "scrolled", x: "1", y: "1", deltaY: delta)
        + forms(kind: "scrolled", x: "1", y: "1", deltaX: delta)
      {
        #expect(pointerEvent(command) == nil, "\(command)")
      }
    }
    // Control: the bound itself, as a delta, on the same forms.
    for command in forms(kind: "scrolled", x: "1", y: "1", deltaY: "-16777216") {
      #expect(
        pointerEvent(command)?.kind == .scrolled(deltaX: 0, deltaY: -16_777_216), "\(command)")
    }
  }

  @Test("w2fb022: probe — decimals above 2^24 that round to it in Double")
  func w2fb022WireDecimalsAboveTheBoundThatRoundToIt() {
    // Observation, recorded in the hypotheses: the bound applies to the parsed
    // value, so these decimal spellings of a larger number are accepted.
    for spelling in ["16777216.0000000001", "1.67772160000000001e7"] {
      #expect(
        pointerEvent("mouse:moved:\(spelling):2:none:0:0:0")?.location.location
          == Point(x: 16_777_216, y: 2), "\(spelling)")
    }
  }

  @Test("w2fb023: every JavaScript String(number) spelling class is accepted with its exact value")
  func w2fb023EveryJavaScriptNumberSpellingClassIsAccepted() {
    // String(n) for: an integer, a negative integer, a fraction below one,
    // a negative fraction, a mixed decimal, two 17-digit shortest round trips,
    // a half below the bound, 1e-6 (the last plain decimal), a negative-exponent
    // value with and without a fraction or sign, the smallest subnormal and a
    // tiny normal.
    let spellings = [
      "0", "7", "-7", "0.5", "-0.25", "123.456", "0.30000000000000004", "0.3333333333333333",
      "16777215.5", "0.000001", "1e-7", "1.5e-7", "-2.5e-8", "5e-324", "1e-300",
    ]
    for spelling in spellings {
      let value = Double(spelling)
      #expect(value != nil, "\(spelling)")
      for command in forms(kind: "moved", x: spelling, y: "1") {
        #expect(
          pointerEvent(command)?.location.location == Point(x: value ?? .nan, y: 1), "\(command)")
      }
    }
  }
}
