// Adversarial set B, pass 4: text figures (371–380).
//
// A TextFigure runs the vendored FIGlet engine twice per frame: once for its
// layout metrics, cached per payload, and once at draw time for the placed
// width. The register ratifies only that a banner ignores lineLimit,
// truncationMode and textWrappingStrategy; everything else is the engine's
// own contract. These probes hand a TheDraw font a space, feed the metrics
// cache two canonically equal strings, propose zero width to content the
// font cannot draw, read a banner's accessibility node, parse a header with
// a negative comment count and a glyph with a short row, and pin the
// ratified ignores, hardblank handling, the cache bounds and right-to-left
// layout.
import SwiftTUIVendorFiglet
import SwiftTUIVendorFigletEmbeddedFonts
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: text figures", .serialized)
struct AdversarialSetBTextFigureTests {
  private func render<V: View>(
    _ view: V, _ name: String, proposal: ProposedSize = .unspecified
  ) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("SetBTextFigure", name)), proposal: proposal)
  }

  private func nodes<V: View>(_ view: V, _ name: String) -> [AccessibilityNode] {
    render(view, name, proposal: .init(width: 60, height: 20)).semanticSnapshot.accessibilityNodes
  }

  private func metrics(
    _ content: String, font: TextFigure.Font = .standard
  ) -> TextFigureLayoutMetrics {
    TextFigureSupport.layoutMetrics(for: .init(content: content, font: font))
  }

  // A space in a TheDraw font separates the glyphs around it: "A B" is wider
  // than "AB" and draws differently.
  @Test func setB371TheDrawFontsKeepTheSpaceBetweenWords() {
    let joined = metrics("AB", font: .font208)
    let spaced = metrics("A B", font: .font208)
    #expect(joined.idealSize.width == 36, "\(joined)")
    let joinedLines = render(TextFigure("AB", font: .font208), "joined").rasterSurface.lines
    let spacedLines = render(TextFigure("A B", font: .font208), "spaced").rasterSurface.lines
    do {
      #expect(spaced.idealSize.width > joined.idealSize.width, "\(spaced) vs \(joined)")
      #expect(spacedLines != joinedLines, "\(spacedLines)")
    }
    // A FIGlet font with a space glyph keeps the gap.
    #expect(metrics("A B").idealSize.width > metrics("AB").idealSize.width)
  }

  // Canonically equal strings are one payload: they draw one figure, and the
  // metrics the cache returns for a string describe what the engine draws
  // for it.
  @Test func setB372CanonicallyEqualContentRendersOneFigure() {
    let precomposed = TextFigurePayload(content: "Ä", font: .standard)
    let decomposed = TextFigurePayload(content: "A\u{308}", font: .standard)
    #expect(precomposed == decomposed)
    let first = render(TextFigure("Ä"), "precomposed")
    let firstLines = first.rasterSurface.lines
    #expect(firstLines.count == 6, "\(firstLines)")
    #expect(firstLines.dropFirst().first == "(_)_(_)", "\(firstLines)")
    let second = render(TextFigure("A\u{308}"), "decomposed")
    let secondLines = second.rasterSurface.lines
    let drawn = TextFigureSupport.render(
      decomposed, boundsWidth: 80, environment: StyleEnvironmentSnapshot())
    let cached = TextFigureSupport.layoutMetrics(for: decomposed)
    do {
      #expect(secondLines == firstLines, "\(secondLines)")
      #expect(secondLines.first != "A\u{308}", "plain-text fallback: \(secondLines)")
      #expect(drawn.size.width <= cached.idealSize.width, "\(drawn.size) vs \(cached)")
    }
  }

  // A zero-width proposal measures what the engine can draw: content without
  // glyphs measures zero at every width, and a lone newline keeps the font
  // height.
  @Test func setB373ZeroWidthProposalsMeasureTheFigureNotThePlainText() {
    let unsupported = TextFigurePayload(content: "日本", font: .standard)
    let newline = TextFigurePayload(content: "\n", font: .standard)
    #expect(TextFigureSupport.layoutMetrics(for: unsupported).idealSize == .zero)
    #expect(
      TextFigureSupport.measuredSize(for: unsupported, proposal: .init(width: 1, height: nil))
        == .zero)
    #expect(
      TextFigureSupport.measuredSize(
        for: unsupported, proposal: .init(width: Int.max, height: nil)) == .zero)
    #expect(
      TextFigureSupport.layoutMetrics(for: newline).idealSize == CellSize(width: 0, height: 6))
    let zeroWidth = TextFigureSupport.measuredSize(
      for: unsupported, proposal: .init(width: 0, height: nil))
    let zeroWidthNewline = TextFigureSupport.measuredSize(
      for: newline, proposal: .init(width: 0, height: nil))
    let snapshot = render(TextFigure("日本"), "zeroWidth", proposal: .init(width: 0, height: 10))
    let rasterIsEmpty = snapshot.rasterSurface.lines.allSatisfy(\.isEmpty)
    #expect(rasterIsEmpty, "\(snapshot.rasterSurface.lines)")
    do {
      #expect(zeroWidth == .zero, "\(zeroWidth)")
      #expect(zeroWidthNewline == CellSize(width: 0, height: 6), "\(zeroWidthNewline)")
      #expect(snapshot.measuredTree.measuredSize == .zero, "\(snapshot.measuredTree.measuredSize)")
    }
  }

  // A banner is text: it publishes its content as its accessibility label
  // and contributes it to a combined group, like Text does.
  @Test func setB374TextFigureContentIsItsAccessibilityLabel() {
    let text = nodes(Text("Hi"), "text")
    #expect(text.contains { $0.label == "Hi" }, "\(text.map(\.label))")
    let labelled = nodes(TextFigure("Hi").accessibilityLabel("Welcome"), "labelled")
    #expect(labelled.contains { $0.label == "Welcome" }, "\(labelled.map(\.label))")
    let figure = nodes(TextFigure("Hi"), "figure")
    let combined = nodes(
      VStack {
        Text("Title")
        TextFigure("Big")
      }
      .accessibilityElement(children: .combine), "combined")
    do {
      #expect(figure.contains { $0.label == "Hi" }, "\(figure.map(\.label))")
      #expect(
        combined.contains { $0.label?.contains("Big") == true }, "\(combined.map(\.label))")
    }
  }

  // A header whose comment-line count is negative is rejected as an invalid
  // font; it never forms an empty-to-negative range.
  @Test func setB375NegativeCommentCountsAreRejectedNotTrapped() async throws {
    let overdeclared = FigletFontLibrary(fontData: ["over": "flf2a$ 1 1 1 0 5\n"])
    #expect(throws: FigletError.self) { try overdeclared.font(named: "over") }
    do {
      await #expect(processExitsWith: .success) {
        let library = FigletFontLibrary(fontData: ["negative": "flf2a$ 1 1 1 0 -1\n"])
        _ = try? library.font(named: "negative")
      }
    }
  }

  // The register ratifies that a banner ignores lineLimit, truncationMode
  // and textWrappingStrategy: its rows and size are unchanged by all three.
  @Test func setB376BannersIgnoreTheTextLayoutEnvironment() {
    let proposal = ProposedSize(width: 8, height: nil)
    let baseline = render(TextFigure("Hi"), "baseline", proposal: proposal)
    #expect(baseline.measuredTree.measuredSize == CellSize(width: 7, height: 12))
    #expect(baseline.rasterSurface.lines.count == 12, "\(baseline.rasterSurface.lines)")
    let variants: [(String, RenderSnapshot)] = [
      ("limited", render(TextFigure("Hi").lineLimit(1), "limited", proposal: proposal)),
      ("cleared", render(TextFigure("Hi").lineLimit(0), "cleared", proposal: proposal)),
      (
        "truncated",
        render(TextFigure("Hi").truncationMode(.head), "truncated", proposal: proposal)
      ),
      (
        "strategy",
        render(
          TextFigure("Hi").textWrappingStrategy(.wordBoundary), "strategy", proposal: proposal)
      ),
    ]
    for (name, snapshot) in variants {
      #expect(
        snapshot.measuredTree.measuredSize == baseline.measuredTree.measuredSize,
        "\(name): \(snapshot.measuredTree.measuredSize)")
      #expect(
        snapshot.rasterSurface.lines == baseline.rasterSurface.lines,
        "\(name): \(snapshot.rasterSurface.lines)")
    }
  }

  // Hardblanks are layout-only space: a trailing space widens the measured
  // figure but adds no ink, a DEL hardblank never reaches the raster, and a
  // full-width font's space glyph is exactly its own width.
  @Test func setB377HardblanksAreLayoutOnlySpace() {
    let plain = render(TextFigure("Hi"), "plain")
    let trailing = render(TextFigure("Hi "), "trailing")
    #expect(plain.measuredTree.measuredSize == CellSize(width: 9, height: 6))
    #expect(
      trailing.measuredTree.measuredSize == CellSize(width: 10, height: 6),
      "\(trailing.measuredTree.measuredSize)")
    #expect(trailing.rasterSurface.lines == plain.rasterSurface.lines)
    let future = render(TextFigure("A B", font: .future), "future")
    #expect(
      !future.rasterSurface.lines.joined().contains("\u{7F}"), "\(future.rasterSurface.lines)")
    let futureJoined = metrics("AB", font: .future)
    let futureSpaced = metrics("A B", font: .future)
    #expect(futureJoined.idealSize == CellSize(width: 6, height: 3), "\(futureJoined)")
    #expect(futureSpaced.idealSize.width == futureJoined.idealSize.width + 3, "\(futureSpaced)")
  }

  // The metrics cache stays within its 256-entry capacity under distinct
  // payloads, and repeated hits on one payload do not grow its recency log.
  @Test func setB378MetricsCacheStaysBoundedUnderFillsAndHits() throws {
    func snapshot() throws -> MemoryMetricSnapshot {
      try #require(
        MemoryMetricRegistry.shared.snapshotAll().first {
          $0.name == "TextFigureSupport.metricsCache"
        })
    }
    for index in 0..<300 {
      _ = TextFigureSupport.layoutMetrics(for: .init(content: "b378-\(index)", font: .small))
    }
    let filled = try snapshot()
    #expect(filled.count <= 256, "\(filled)")
    let hot = TextFigurePayload(content: "b378-hot", font: .small)
    _ = TextFigureSupport.layoutMetrics(for: hot)
    let before = try snapshot()
    for _ in 0..<1000 {
      _ = TextFigureSupport.layoutMetrics(for: hot)
    }
    let after = try snapshot()
    #expect(after.count <= 256, "\(after)")
    let growth = (after.detail?["order"] ?? 0) - (before.detail?["order"] ?? 0)
    do {
      #expect(growth < 1000, "order grew by \(growth)")
    }
  }

  // A glyph row shorter than the smush amount is a font defect the engine
  // tolerates (render or reject); it never indexes past the row.
  @Test func setB379RaggedGlyphRowsDoNotTrapTheSmusher() async throws {
    let library = FigletFontLibrary(fontData: ["ragged": SetBFigletFonts.raggedKerningFont])
    let font = try #require(try library.font(named: "ragged"))
    let leading = try Figlet(font: font, configuration: .init(width: 80)).render("ba")
    #expect(leading.rawValue.contains("b"), "\(leading.rawValue)")
    do {
      await #expect(processExitsWith: .success) {
        let library = FigletFontLibrary(fontData: ["ragged": SetBFigletFonts.raggedKerningFont])
        guard let font = try? library.font(named: "ragged") else {
          return
        }
        _ = try? Figlet(font: font, configuration: .init(width: 80)).render("ab")
      }
    }
  }

  // Right-to-left layout prepends each glyph, smushes across the seam and
  // right-justifies to one column short of the configured width, as figlet
  // does.
  @Test func setB380RightToLeftLayoutPrependsGlyphsAndRightJustifies() throws {
    let font = try #require(try EmbeddedFigletFont.library.font(named: "standard"))
    let rightToLeft = Figlet(
      font: font, configuration: .init(width: 20, direction: .rightToLeft))
    let rows = try rightToLeft.renderSurface("Hi").rows.map { String($0.map(\.character)) }
    #expect(
      rows == [
        "           _ _   _ ",
        "          (_) | | |",
        "          | | |_| |",
        "          | |  _  |",
        "          |_|_| |_|",
        "                   ",
      ], "\(rows)")
    #expect(rows.allSatisfy { $0.count == 19 }, "\(rows.map(\.count))")
    let leftToRight = try Figlet(font: font, configuration: .init(width: 20)).renderSurface("Hi")
    #expect(
      leftToRight.rows.first.map { String($0.map(\.character)) } == " _   _ _ ",
      "\(leftToRight.rows.map { String($0.map(\.character)) })")
  }
}

/// A hand-built kerning font (old layout 0, height 2) for the parser and
/// smusher probes: "a" is a full five-column block, "b" has an empty first
/// row, and every other glyph is empty so it is dropped at parse time.
private enum SetBFigletFonts {
  static let raggedKerningFont: String = {
    var lines = ["flf2a$ 2 1 5 0 0"]
    for code in 32..<127 {
      switch code {
      case 97:
        lines += ["a    @", "aaaaa@@"]
      case 98:
        lines += ["@", " b@@"]
      default:
        lines += ["@", "@@"]
      }
    }
    return lines.joined(separator: "\n") + "\n"
  }()
}
