// Adversarial set B, pass 2: output encoding at the presentation boundary
// (171–180).
//
// The terminal renderer, the web-surface wire and the style transport each
// serialize the same raster cells. The architecture notes fix the boundary
// rule: presentation sanitizes authored text and OSC 8 destinations. These
// probes hand each encoder a cell shape the rasterizer can legitimately
// produce (zero-width clusters, a wide lead in the last column, format and
// control scalars, empty link destinations, translucent theme colors) and
// check that the encoders agree with each other and with that rule.
import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@Suite("Adversarial set B: output encoding")
struct AdversarialSetBEncodingTests {
  private func escapes(in text: String) -> Int {
    text.unicodeScalars.filter { $0.value == 0x1B }.count
  }

  // A zero-width cluster occupies one raster cell but advances the terminal
  // cursor by nothing; the batch renderer's cursor bookkeeping must still put
  // the next span in its column.
  @Test func setB171ZeroWidthCellKeepsLaterSpansInTheirColumns() throws {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .previewUnicode)
    let row = [
      RasterCell(character: "a"), RasterCell(character: "\u{200B}"), RasterCell(character: " "),
      RasterCell(character: "X"),
    ]
    let batch = try #require(
      renderer.renderRowBatch(row: 0, currentRow: row, spans: [1..<2, 3..<4]))
    let rendered = batch.renderedBatch
    // A full row paints the zero-width cell without displacing its neighbors.
    let full = renderer.render(RasterSurface(size: .init(width: 4, height: 1), cells: [row]))
    let visible = full.unicodeScalars.filter { $0.value != 0x200B }
    withKnownIssue(
      "a zero-width cell is counted as one column, so the next glyph lands one column early"
    ) {
      #expect(
        rendered == " \u{1B}[1CX" || rendered == "\u{200B}\u{1B}[2CX" || rendered == "\u{200B} X",
        "\(rendered.debugDescription)")
      #expect(String(String.UnicodeScalarView(visible)) == "a  X", "\(full.debugDescription)")
    }
  }

  // A wide glyph whose lead sits in the last column is a surface the raster
  // produces (set B 041); the web host must encode it, not reject the frame.
  @Test func setB172WideLeadInTheLastColumnIsEncodedNotRejected() {
    let surface = RasterSurface(
      size: .init(width: 4, height: 1),
      cells: [
        [
          RasterCell(character: "a"), RasterCell(character: "b"), RasterCell(character: "c"),
          RasterCell(character: "漢", spanWidth: 2),
        ]
      ])
    let terminal = TerminalSurfaceRenderer(capabilityProfile: .previewUnicode).render(surface)
    #expect(terminal == "abc漢", "\(terminal.debugDescription)")
    let encoded = WebSurfaceFrameEncoder.encode(surface)
    withKnownIssue(
      "HostWireBudget.validate rejects a span wider than the cells left in the row, so the frame is dropped"
    ) {
      #expect(encoded.hasPrefix("\u{1E}surface:"), "\(encoded.prefix(80))")
      #expect(encoded != HostWireBudget.rejectionRecord)
      #expect(encoded.contains("漢"), "\(encoded.prefix(200))")
    }
  }

  // DEL and C1 control scalars are escaped by every JSON writer at the
  // boundary, as the frame renderer already does.
  @Test func setB173JSONWritersEscapeDELAndC1Controls() {
    let text = "a\u{7F}\u{85}\u{9B}b"
    let wire = WebSurfaceFrameEncoder.jsonString(text)
    #expect(wire.hasPrefix("\"a") && wire.hasSuffix("b\""), "\(wire.debugDescription)")
    let transport = styleTransportJSONStringLiteral(text)
    withKnownIssue(
      "the wire and transport writers escape 0x00–0x1F only; DEL and C1 ship raw (STUI-868 class)"
    ) {
      #expect(
        !wire.unicodeScalars.contains { (0x7F...0x9F).contains($0.value) },
        "\(wire.debugDescription)")
      #expect(
        !transport.unicodeScalars.contains { (0x7F...0x9F).contains($0.value) },
        "\(transport.debugDescription)")
    }
    // C0 controls and the structural characters are escaped everywhere.
    let c0 = WebSurfaceFrameEncoder.jsonString("x\u{01}\"\\\n")
    #expect(c0 == "\"x\\u0001\\\"\\\\\\n\"", "\(c0.debugDescription)")
    #expect(styleTransportJSONStringLiteral("x\u{01}\"\\\n") == c0)
  }

  // An empty or fully sanitized hyperlink destination is no link: the
  // terminal renderer emits the glyph alone, with no OSC 8 pair around it.
  @Test func setB174EmptyLinkDestinationsEmitNoHyperlinkSequence() {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    func render(_ destination: String?) -> String {
      renderer.render(
        RasterSurface(
          size: .init(width: 1, height: 1),
          cells: [[RasterCell(character: "X", hyperlink: destination)]]))
    }
    #expect(render(nil) == "X", "\(render(nil).debugDescription)")
    withKnownIssue(
      "an empty or fully sanitized destination still opens and closes an OSC 8 envelope"
    ) {
      #expect(render("") == "X", "\(render("").debugDescription)")
      #expect(render("\u{07}") == "X", "\(render("\u{07}").debugDescription)")
      #expect(render("\u{1B}\u{1B}") == "X", "\(render("\u{1B}\u{1B}").debugDescription)")
    }
    let real = render("https://example.test/a")
    #expect(
      real.contains("\u{1B}]8;;https://example.test/a\u{1B}\\X\u{1B}]8;;\u{1B}\\"),
      "\(real.debugDescription)")
  }

  // The style transport round-trips theme colors with their alpha and does
  // not silently flatten a translucent selection color to opaque.
  @Test func setB175StyleTransportKeepsThemeColorAlpha() throws {
    let style = TerminalRenderStyle(
      appearance: .init(
        foregroundColor: Color(hexRGB: 0x102030), backgroundColor: Color(hexRGB: 0x405060),
        tintColor: Color(hexRGB: 0x708090), palette: [0: Color(hexRGB: 0x000000)],
        colorSchemeContrast: .standard, source: .override),
      theme: .init(
        foreground: Color(hexRGB: 0xABCDEF), background: Color(hexRGB: 0x012345),
        tint: Color(hexRGB: 0x456789), separator: Color(hexRGB: 0x111111),
        selection: Color(hexRGB: 0x222222).withAlpha(0.5), placeholder: Color(hexRGB: 0x333333),
        link: Color(hexRGB: 0x444444), fill: Color(hexRGB: 0x555555),
        windowBackground: Color(hexRGB: 0x666666), success: Color(hexRGB: 0x777777),
        warning: Color(hexRGB: 0x888888), danger: Color(hexRGB: 0x999999),
        info: Color(hexRGB: 0xAAAAAA), muted: Color(hexRGB: 0xBBBBBB)))
    let encoded = try #require(TerminalRenderStyleCodec.encodeBase64(style))
    let decoded = try #require(TerminalRenderStyleCodec.decodeBase64(encoded))
    let selection = try #require(decoded.theme?.selection)
    withKnownIssue("colors travel as #rrggbb, so a translucent theme color decodes opaque") {
      #expect(abs(selection.alpha - 0.5) < 1e-6, "\(selection)")
      #expect(decoded == style)
    }
  }

  // Assistive text keeps its letters: a label with accents or CJK must not be
  // read out as question marks.
  @Test func setB176AssistiveTextSanitizerKeepsNonASCIILetters() {
    let sanitizer = AccessibilityTextSanitizer()
    withKnownIssue("the sanitizer keeps printable ASCII only and turns every other scalar into ?") {
      #expect(sanitizer.sanitized("Café 日本") == "Café 日本")
      #expect(sanitizer.sanitized("naïve résumé") == "naïve résumé")
    }
    let escaped = sanitizer.sanitized("a\u{1B}[31mb") ?? ""
    #expect(!escaped.unicodeScalars.contains("\u{1B}"), "\(escaped.debugDescription)")
    #expect(escaped.hasPrefix("a") && escaped.hasSuffix("[31mb"), "\(escaped.debugDescription)")
    #expect(sanitizer.sanitized("tab\tsep") == "tab sep")
    #expect(sanitizer.sanitized("  padded  ") == "padded")
    #expect(sanitizer.sanitized("") == nil)
  }

  // Bidirectional and other format controls are text controls: the terminal
  // never receives a right-to-left override or an isolate raw.
  @Test func setB177FormatControlsNeverReachTheTerminalRaw() {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    for (name, control) in [
      ("RLO", "\u{202E}"), ("LRE", "\u{202A}"), ("FSI", "\u{2068}"), ("PDI", "\u{2069}"),
      ("LRM", "\u{200E}"),
    ] {
      let surface = RasterSurface(
        size: .init(width: 3, height: 1),
        cells: [
          [
            RasterCell(character: "a"), RasterCell(character: Character(control)),
            RasterCell(character: "b"),
          ]
        ])
      let rendered = renderer.render(surface)
      #expect(
        rendered.contains("a") && rendered.contains("b"), "\(name): \(rendered.debugDescription)")
      withKnownIssue(
        "only C0, DEL and C1 are blanked; bidi and other format controls reach the terminal raw"
      ) {
        #expect(
          !rendered.unicodeScalars.contains(control.unicodeScalars.first!),
          "\(name) reached the terminal: \(rendered.debugDescription)")
      }
    }
    // C0 and C1 controls in a cell are already blanked.
    let c1 = renderer.render(
      RasterSurface(size: .init(width: 1, height: 1), cells: [[RasterCell(character: "\u{9B}")]]))
    #expect(!c1.unicodeScalars.contains("\u{9B}"), "\(c1.debugDescription)")
  }

  // A hyperlink destination can carry a semicolon and a scheme, but never a
  // BEL, an ESC or a newline that would end or split the OSC 8 envelope.
  @Test func setB178HyperlinkDestinationsCannotBreakTheirEnvelope() throws {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .trueColor)
    let destination = "https://example.test/a;b\u{07}c\u{1B}\\d\ne=f"
    let rendered = renderer.render(
      RasterSurface(
        size: .init(width: 1, height: 1),
        cells: [[RasterCell(character: "X", hyperlink: destination)]]))
    let open = "\u{1B}]8;;"
    let terminator = "\u{1B}\\"
    let openRange = try #require(rendered.range(of: open))
    let afterOpen = rendered[openRange.upperBound...]
    let terminatorRange = try #require(afterOpen.range(of: terminator))
    let emitted = String(afterOpen[..<terminatorRange.lowerBound])
    #expect(
      !emitted.unicodeScalars.contains { $0.value < 0x20 || $0.value == 0x7F },
      "\(emitted.debugDescription)")
    #expect(emitted.hasPrefix("https://example.test/a;b"), "\(emitted.debugDescription)")
    #expect(emitted.contains("e=f"), "\(emitted.debugDescription)")
    let closes = rendered.components(separatedBy: open).count - 1
    #expect(closes == 2, "one open and one close: \(rendered.debugDescription)")
  }

  // Style runs coalesce: one SGR per run, one reset where the style ends,
  // and no redundant sequences between identically styled cells.
  @Test func setB179StyleRunsEmitOneSequencePerTransition() {
    let renderer = TerminalSurfaceRenderer(capabilityProfile: .ansi16)
    let red = ResolvedTextStyle(foregroundColor: Color(hexRGB: 0xFF0000))
    let uniform = renderer.render(
      RasterSurface(
        size: .init(width: 3, height: 1), lines: ["abc"],
        styleRuns: [.init(x: 0, y: 0, length: 3, style: red)]))
    #expect(escapes(in: uniform) == 2, "\(uniform.debugDescription)")
    #expect(uniform.hasSuffix("abc\u{1B}[0m"), "\(uniform.debugDescription)")

    let split = renderer.render(
      RasterSurface(
        size: .init(width: 2, height: 1), lines: ["ab"],
        styleRuns: [.init(x: 0, y: 0, length: 1, style: red)]))
    #expect(escapes(in: split) == 2, "\(split.debugDescription)")
    #expect(split.hasSuffix("b"), "\(split.debugDescription)")

    let plain = renderer.render(RasterSurface(size: .init(width: 2, height: 1), lines: ["ab"]))
    #expect(escapes(in: plain) == 0, "\(plain.debugDescription)")
  }

  // The wire budget counts exactly the bytes the JSON writer emits, for
  // every escaping class.
  @Test func setB180WireBudgetCountsTheBytesTheWriterEmits() throws {
    for text in [
      "plain", "", "a\u{0}b", "\u{7F}", "\u{85}", "\u{2028}\u{2029}", "😀", "quote\"back\\",
      "tab\tnl\ncr\r", "漢字", "e\u{0301}",
    ] {
      let written = WebSurfaceFrameEncoder.jsonString(text).utf8.count
      let budgeted = try HostWireBudget.jsonStringBytes(text)
      #expect(
        written == budgeted, "\(text.debugDescription): written \(written) budgeted \(budgeted)")
    }
  }
}
