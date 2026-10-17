// Adversarial set B, pass 2: color math and terminal color quantization
// (151–160).
//
// `Color` is a concrete channel value with hex parsing, perceptual mixing,
// OKLCH adjustments and alpha compositing, and the terminal renderer
// quantizes it to the ANSI palettes. The register ratifies clamped mixing
// fractions and multiplied alpha; these probes sit on the grammar, the NaN
// and out-of-range edges of every clamp, the fidelity of the palette
// mappings, and the round trips through hex and hue.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("Adversarial set B: color")
struct AdversarialSetBColorTests {
  private func approximately(_ a: Color, _ b: Color, tolerance: Double = 1e-6) -> Bool {
    abs(a.red - b.red) <= tolerance && abs(a.green - b.green) <= tolerance
      && abs(a.blue - b.blue) <= tolerance && abs(a.alpha - b.alpha) <= tolerance
  }

  // Hex grammar: three, four, six and eight digits with or without the hash
  // and surrounding whitespace parse; everything else throws instead of
  // guessing.
  @Test func setB151HexGrammarAcceptsCSSFormsAndRejectsTheRest() throws {
    #expect(try Color(hex: "#F00") == Color(hexRGB: 0xFF0000))
    #expect(try Color(hex: "FF0000") == Color(hexRGB: 0xFF0000))
    #expect(try Color(hex: " #ff0000 ") == Color(hexRGB: 0xFF0000))
    let shortAlpha = try Color(hex: "#F00A")
    #expect(abs(shortAlpha.alpha - 170.0 / 255.0) < 1e-9, "\(shortAlpha.alpha)")
    let longAlpha = try Color(hex: "#FF0000AA")
    #expect(abs(longAlpha.alpha - 170.0 / 255.0) < 1e-9, "\(longAlpha.alpha)")
    #expect(try Color(hex: "#abc") == Color(hex: "#AABBCC"))

    for invalid in ["0xFF0000", "#12345", "#1234567", "", "#", "##FFF", "#GGG", "#FF 000"] {
      #expect(throws: ColorError.self, "\(invalid) parsed") {
        try Color(hex: invalid)
      }
    }
  }

  // Every clamp treats NaN as its lower end and out-of-range input as the
  // nearer end: opacity, alpha, gradient stop locations.
  @Test func setB152ClampsAgreeOnNaNAndOutOfRangeInputs() async {
    #expect(Color.red.opacity(2).alpha == 1)
    #expect(Color.red.opacity(-1).alpha == 0)
    #expect(Color.red.withAlpha(2).alpha == 1)
    #expect(Color.red.withAlpha(-1).alpha == 0)
    // NaN reaches the clamps of three sibling APIs; each must land on an end.
    await #expect(processExitsWith: .success) {
      #expect(Color.red.opacity(.nan).alpha == 0)
    }
    do {
      await #expect(processExitsWith: .success) {
        #expect(Color.red.withAlpha(.nan).alpha == 0)
      }
    }
    await #expect(processExitsWith: .success) {
      #expect(Gradient.Stop(color: .red, location: .nan).location == 0)
    }
    #expect(Gradient.Stop(color: .red, location: 7).location == 1)
    #expect(Gradient.Stop(color: .red, location: -.infinity).location == 0)
    // `.opacity` multiplies the stored alpha; it never raises it.
    #expect(Color.red.withAlpha(0.5).opacity(2).alpha == 0.5)
    #expect(abs(Color.red.withAlpha(0.5).opacity(0.5).alpha - 0.25) < 1e-12)
    // Negative zero is black, equal and hash-equal.
    let negativeZero = Color(red: -0.0, green: 0, blue: 0)
    #expect(negativeZero == .black)
    #expect(negativeZero.hashValue == Color.black.hashValue)
  }

  // A zero-span angular gradient splits the circle at the point opposite its
  // start between the last and the first color; a negative multi-turn span
  // runs counter-clockwise over its last complete turn.
  @Test func setB153DegenerateAngularSpansFollowTheMissingAreaRule() {
    let zeroSpan = AngularGradient(
      gradient: Gradient(colors: [.red, .blue]), center: .center, startAngle: .zero, endAngle: .zero
    )
    #expect(zeroSpan.location(atAngle: 0.5) == 1, "\(zeroSpan.location(atAngle: 0.5))")
    #expect(zeroSpan.location(atAngle: 3) == 1, "\(zeroSpan.location(atAngle: 3))")
    #expect(zeroSpan.location(atAngle: -0.5) == 0, "\(zeroSpan.location(atAngle: -0.5))")
    #expect(zeroSpan.location(atAngle: -3) == 0, "\(zeroSpan.location(atAngle: -3))")
    #expect(zeroSpan.location(atAngle: .pi) == 0, "\(zeroSpan.location(atAngle: .pi))")
    let location = zeroSpan.location(atAngle: .nan)
    #expect(location.isFinite && (0...1).contains(location), "\(location)")

    let negative = AngularGradient(
      gradient: Gradient(colors: [.red, .blue]), center: .center, startAngle: .zero,
      endAngle: .radians(-3 * .pi))
    let quarter = negative.location(atAngle: -.pi / 2)
    #expect(abs(quarter - 5.0 / 6.0) < 1e-9, "\(quarter)")
    let full = AngularGradient(
      gradient: Gradient(colors: [.red, .blue]), center: .center, startAngle: .zero,
      endAngle: .radians(4 * .pi))
    // Two turns: the last complete turn is drawn, so half way round reads
    // three quarters of the whole span.
    let half = full.location(atAngle: .pi)
    #expect(abs(half - 0.75) < 1e-9, "\(half)")
  }

  // A translucent foreground is not emitted as a fully opaque color: with no
  // known terminal backdrop it fades toward the fallback theme background,
  // as the rasterizer's own `.opacity` does.
  @Test func setB154TranslucentForegroundIsNotEmittedOpaque() {
    func emit(_ renderer: TerminalCellTextRenderer, alpha: Double) -> String {
      var output = ""
      var state = TerminalCellTextRenderer.RenderState()
      renderer.appendRenderedCells(
        in: [
          RasterCell(
            character: "x", style: .init(foregroundColor: Color(hexRGB: 0xFF0000, alpha: alpha)))
        ],
        from: 0, to: 1, into: &output, state: &state)
      return output
    }
    let backdropped = TerminalCellTextRenderer(
      capabilityProfile: .trueColor, terminalBackgroundColor: .black)
    #expect(emit(backdropped, alpha: 1) != emit(backdropped, alpha: 0.5))
    #expect(emit(backdropped, alpha: 1).contains("38;2;255;0;0"), "\(emit(backdropped, alpha: 1))")

    let unknown = TerminalCellTextRenderer(capabilityProfile: .trueColor)
    let opaque = emit(unknown, alpha: 1)
    let translucent = emit(unknown, alpha: 0.5)
    do {
      #expect(opaque != translucent, "both emit \(opaque)")
      #expect(!translucent.contains("38;2;255;0;0"), "\(translucent)")
    }
  }

  // ANSI-16 quantization keeps the normal-intensity codes: a dark primary
  // maps to 31–37, not to its bright sibling.
  @Test func setB155ANSI16QuantizationUsesNormalIntensityCodes() {
    let renderer = TerminalCellTextRenderer(capabilityProfile: .ansi16)
    let expectations: [(hex: UInt32, code: Int)] = [
      (0x000000, 30), (0x800000, 31), (0x008000, 32), (0x808000, 33), (0x000080, 34),
      (0x800080, 35), (0x008080, 36), (0xC0C0C0, 37), (0x808080, 90), (0xFF0000, 91),
      (0x00FF00, 92), (0xFFFF00, 93), (0x0000FF, 94), (0xFF00FF, 95), (0x00FFFF, 96),
      (0xFFFFFF, 97),
    ]
    for entry in expectations {
      let code = renderer.closestANSI16ForegroundCode(for: Color(hexRGB: entry.hex))
      do {
        #expect(code == entry.code, "\(String(entry.hex, radix: 16)) → \(code)")
      }
    }
  }

  // Explicit short formats quantize to nibbles; ARGB formats put alpha first.
  // The CSS parser accepts RGB/RGBA, so reorder an ARGB export before parsing.
  @Test func setB156HexExportRoundTripsAccordingToItsExplicitFormat() throws {
    let translucent = Color(hexRGBA: 0xFF00_0080)
    #expect(translucent.hexString(format: .rrggbbaa) == "#FF000080")
    #expect(translucent.hexString(format: .aarrggbb) == "#80FF0000")
    #expect(Color(hexRGB: 0xFF0000).hexString(format: .rgb) == "#F00")
    #expect(
      Color(hexRGB: 0xFF0000).hexString(format: .rgb, letterCase: .lowercase, prefix: false)
        == "f00")
    let source = Color(hexRGBA: 0x1234_5678)
    for format in [HexFormat.rgb, .rgba, .rrggbb, .rrggbbaa, .argb, .aarrggbb] {
      let exported = source.hexString(format: format, prefix: false)
      let alphaPrefix: Int
      switch format {
      case .argb: alphaPrefix = 1
      case .aarrggbb: alphaPrefix = 2
      default: alphaPrefix = 0
      }
      let css = String(exported.dropFirst(alphaPrefix)) + String(exported.prefix(alphaPrefix))
      let parsed = try Color(hex: css)
      let short = format == .rgb || format == .rgba || format == .argb
      let tolerance = short ? 1.0 / 30 : 1.0 / 255
      let expected = format == .rgb || format == .rrggbb ? source.withAlpha(1) : source
      #expect(approximately(parsed, expected, tolerance: tolerance), "\(format): \(exported)")
    }
  }

  // Gradient stops are addressed by location, not by array order, and a stop
  // pushed past the unit range after construction samples without trapping.
  @Test @MainActor func setB157GradientStopsResolveByLocationNotArrayOrder() throws {
    var gradient = Gradient(colors: [.red, .blue])
    gradient.stops = [
      Gradient.Stop(color: Color(hexRGB: 0x0000FF), location: 1),
      Gradient.Stop(color: Color(hexRGB: 0xFF0000), location: 0),
    ]
    let reversed = DefaultRenderer().render(
      Rectangle().fill(
        LinearGradient(gradient: gradient, startPoint: .leading, endPoint: .trailing)),
      context: .init(identity: testIdentity("SetBColor", "reversed")),
      proposal: .init(width: 5, height: 1)
    ).rasterSurface.cells
    let first = try #require(reversed[0][0].style?.backgroundColor)
    let last = try #require(reversed[0][4].style?.backgroundColor)
    #expect(first.red > first.blue && last.blue > last.red)
    let ordered = DefaultRenderer().render(
      Rectangle().fill(
        LinearGradient(
          colors: [Color(hexRGB: 0xFF0000), Color(hexRGB: 0x0000FF)],
          startPoint: .leading, endPoint: .trailing)),
      context: .init(identity: testIdentity("SetBColor", "ordered")),
      proposal: .init(width: 5, height: 1)
    ).rasterSurface.cells
    #expect(reversed == ordered, "mutated stops match a canonically ordered gradient")

    var escaped = Gradient(colors: [.red, .blue])
    escaped.stops[1].location = 2
    let overflow = DefaultRenderer().render(
      Rectangle().fill(
        LinearGradient(gradient: escaped, startPoint: .leading, endPoint: .trailing)),
      context: .init(identity: testIdentity("SetBColor", "escaped")),
      proposal: .init(width: 5, height: 1)
    ).rasterSurface.cells
    for cell in overflow[0] {
      let color = try #require(cell.style?.backgroundColor)
      #expect(color.red.isFinite && color.green.isFinite && color.blue.isFinite, "\(color)")
      #expect((0...1).contains(color.red) && (0...1).contains(color.blue), "\(color)")
    }
  }

  // Hue rotation is a round trip: a full turn is the identity and achromatic
  // colors never pick up chroma or NaN.
  @Test func setB158HueRotationRoundTripsAndLeavesGraysAlone() {
    let base = Color(hexRGB: 0x3366CC)
    #expect(approximately(base.rotatedHue(by: 360), base), "\(base.rotatedHue(by: 360))")
    #expect(approximately(base.rotatedHue(by: -720), base), "\(base.rotatedHue(by: -720))")
    #expect(approximately(base.rotatedHue(by: 90).rotatedHue(by: -90), base))
    let quarter = base.rotatedHue(by: 90)
    #expect(!approximately(quarter, base), "a quarter turn changes the hue")
    for gray in [Color.black, .white, Color(white: 0.5, alpha: 1)] {
      let rotated = gray.rotatedHue(by: 123)
      #expect(approximately(rotated, gray, tolerance: 1e-3), "\(gray) → \(rotated)")
      let saturated = gray.saturated(by: 1)
      #expect(saturated.red.isFinite && saturated.green.isFinite && saturated.blue.isFinite)
      #expect(approximately(saturated, gray, tolerance: 1e-3), "\(gray) → \(saturated)")
    }
    let huge = base.rotatedHue(by: 1e12)
    #expect(huge.red.isFinite && huge.green.isFinite && huge.blue.isFinite, "\(huge)")
  }

  // Lightness adjustments saturate at white and black and stay finite for
  // any amount; a negative lighten is a darken.
  @Test func setB159LightnessAdjustmentsSaturateAndStayFinite() {
    let white = Color.red.lightened(by: 5)
    #expect(white.red <= 1 && white.green <= 1 && white.blue <= 1, "\(white)")
    #expect(white.red.isFinite && white.green.isFinite && white.blue.isFinite)
    let lighter = Color.red.lightened(by: 1)
    #expect(lighter.relativeLuminance > Color.red.relativeLuminance, "\(lighter)")
    let black = Color.red.darkened(by: 5)
    do {
      #expect(black.red >= 0 && black.green >= 0 && black.blue >= 0, "\(black)")
    }
    #expect(
      approximately(Color.red.darkened(by: 1), .black, tolerance: 1e-3),
      "\(Color.red.darkened(by: 1))")
    let dimmed = Color.red.lightened(by: -0.2)
    #expect(dimmed.relativeLuminance < Color.red.relativeLuminance, "\(dimmed)")
    #expect(approximately(Color.red.lightened(by: 0), .red, tolerance: 1e-6))
    let infinite = Color.red.lightened(by: .infinity)
    #expect(
      infinite.red.isFinite && infinite.green.isFinite && infinite.blue.isFinite, "\(infinite)")
    #expect(Color.red.lightened(by: 0.3).alpha == 1)
    #expect(Color.red.withAlpha(0.4).darkened(by: 0.3).alpha == 0.4)
  }

  // Alpha compositing: a fully transparent source yields the backdrop, an
  // opaque one yields itself, and translucent over translucent accumulates.
  @Test func setB160AlphaCompositingObeysTheEndpoints() {
    let over = Color(hexRGB: 0xFF0000)
    let under = Color(hexRGB: 0x0000FF)
    #expect(approximately(over.withAlpha(0).composited(over: under), under, tolerance: 1e-6))
    #expect(approximately(over.withAlpha(1).composited(over: under), over, tolerance: 1e-6))
    let half = over.withAlpha(0.5).composited(over: under)
    #expect(half.alpha == 1, "\(half)")
    #expect(half.red > 0.3 && half.red < 0.8 && half.blue > 0.3 && half.blue < 0.8, "\(half)")
    let stacked = over.withAlpha(0.5).composited(over: under.withAlpha(0.5))
    #expect(abs(stacked.alpha - 0.75) < 1e-9, "\(stacked)")
    let overNothing = over.withAlpha(0.5).composited(over: under.withAlpha(0))
    #expect(abs(overNothing.alpha - 0.5) < 1e-9, "\(overNothing)")
    #expect(approximately(overNothing.withAlpha(1), over, tolerance: 1e-6), "\(overNothing)")
  }
}
