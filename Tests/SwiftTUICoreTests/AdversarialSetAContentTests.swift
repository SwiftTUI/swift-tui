import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Adversarial set A: content boundaries and sample grids")
struct AdversarialSetAContentTests {
  // Hypothesis: normalization deduplicates independent links by URL and loses an action owner.
  @Test func setA276AdjacentEqualDestinationsKeepIndependentLinkOwners() {
    let left = RichTextRun(text: "left", destination: "https://example.org", linkIdentifier: "left")
    let right = RichTextRun(
      text: "right", destination: "https://example.org", linkIdentifier: "right")
    let payload = RichTextPayload(runs: [left, right])
    #expect(payload.visibleText == "leftright")
    #expect(payload.runs.count == 2)
    #expect(payload.linkCount == 2)
    #expect(payload.runs.map(\.linkIdentifier) == ["left", "right"])
  }

  // Hypothesis: CRLF's single Swift Character bypasses the layout line-separator classifier.
  @Test func setA277CRLFDocumentsHaveTheSameLogicalRowsAsLF() {
    let windows = layoutText(for: "north\r\n\r\nsouth\r\n", width: 12)
    let unix = layoutText(for: "north\n\nsouth\n", width: 12)
    #expect(unix.lines.map(\.text) == ["north", "", "south", ""])
    withKnownIssue("STUI-961: text layout does not recognize a CRLF Character as a line break") {
      #expect(windows.lines.map(\.text) == unix.lines.map(\.text))
      #expect(windows.size == unix.size)
    }
  }

  // Hypothesis: synthetic word-continuation markers accidentally consume source caret offsets.
  @Test func setA278CaretOffsetsSkipSyntheticContinuationMarkers() {
    let text = "ABCDEFG"
    #expect(
      layoutText(for: text, width: 3).lines.map(\.text) == ["AB–", "–C–", "–D–", "–E–", "–FG"])
    let anchors = wrappedTextCursorAnchors(text, width: 3)
    #expect(
      anchors == [
        CellPoint(x: 0, y: 0), CellPoint(x: 1, y: 0), CellPoint(x: 1, y: 1),
        CellPoint(x: 1, y: 2), CellPoint(x: 1, y: 3), CellPoint(x: 1, y: 4),
        CellPoint(x: 2, y: 4), CellPoint(x: 3, y: 4),
      ])
  }

  // Hypothesis: a style-run boundary gets mistaken for a word boundary during wrapping.
  @Test func setA279StylingInsideAWordCannotChangeItsLineBreaks() {
    let rich = RichTextPayload(runs: [
      .init(text: "AB", style: .init(foregroundStyle: .color(.red))),
      .init(text: "CD", style: .init(foregroundStyle: .color(.blue))),
      .init(text: "EFG"),
    ])
    let plain = layoutText(for: rich.visibleText, width: 4)
    #expect(plain.lines.count > 1)
    #expect(
      layoutRichText(for: rich, options: .init(width: 4)).lines.map(\.text)
        == plain.lines.map(\.text))
  }

  // Hypothesis: rich-layout cache identity ignores changed run partitioning when visible text matches.
  @Test func setA280WarmRichLayoutDoesNotReuseOldRunIndices() {
    let first = RichTextPayload(runs: [.init(text: "AB"), .init(text: "CD", destination: "one")])
    let second = RichTextPayload(runs: [.init(text: "A"), .init(text: "BCD", destination: "two")])
    let options = TextLayoutOptions(width: 8)
    #expect(
      layoutRichText(for: first, options: options).lines[0].clusters.map(\.runIndex)
        == [0, 0, 1, 1])
    #expect(
      layoutRichText(for: second, options: options).lines[0].clusters.map(\.runIndex)
        == [0, 1, 1, 1])
    #expect(
      layoutRichText(for: first, options: options).lines[0].clusters.map(\.runIndex)
        == [0, 0, 1, 1])
  }

  // Hypothesis: an invisible standalone format cluster consumes terminal width and forces a wrap.
  @Test func setA281ZeroWidthFormatClustersDoNotStealVisibleCells() {
    let result = layoutText(for: "A\u{200B}B", width: 2)
    #expect(result.size == CellSize(width: 2, height: 1))
    #expect(result.lines[0].clusters.map(\.cellWidth) == [1, 0, 1])
  }

  // Hypothesis: VS15 collapses inherently wide CJK glyphs while selecting text presentation.
  @Test func setA282TextPresentationDoesNotNarrowEastAsianWideGlyphs() {
    #expect(layoutText(for: "漢\u{FE0E}X", width: nil).size.width == 3)
    #expect(layoutText(for: "☀\u{FE0E}X", width: nil).size.width == 2)
  }

  // Hypothesis: negative fractional samples truncate toward zero and paint inside the canvas.
  @Test func setA283NegativeSubcellProjectionCannotPaintOrigin() {
    var context = canvasContext(.sextant2x3)
    #expect(context.gridSample(for: Point(x: -0.01, y: 0.1)) == GridSample(x: -1, y: 0))
    context.setPixel(at: Point(x: -0.01, y: 0.1), foreground: .red)
    #expect(context.canvas.mask(x: 0, y: 0) == 0)
    #expect(context.gridCellStyles[0][0] == nil)
  }

  // Hypothesis: clearing a sample at a cell boundary also clears its neighbor's same local bit.
  @Test func setA284ClearingBoundarySampleLeavesOtherCellIntact() {
    var buffer = CanvasGridBuffer(size: .init(width: 2, height: 1), grid: .braille2x4)
    buffer.setPixel(x: 1, y: 3)
    buffer.setPixel(x: 3, y: 3)
    buffer.clearPixel(x: 1, y: 3)
    #expect(buffer.mask(x: 0, y: 0) == 0)
    #expect(buffer.mask(x: 1, y: 0) == 0x80)
  }

  // Hypothesis: negative rectangle origins shift rather than clip the supplied coverage.
  @Test func setA285PartiallyOffscreenFillKeepsItsOriginalExtent() {
    var buffer = CanvasGridBuffer(size: .init(width: 3, height: 2), grid: .quadrant2x2)
    buffer.fillRect(x: -1, y: -1, width: 4, height: 3)
    #expect(buffer.mask(x: 0, y: 0) == 15)
    #expect(buffer.mask(x: 1, y: 0) == 5)
    #expect(buffer.mask(x: 2, y: 0) == 0)
    #expect((0..<3).allSatisfy { buffer.mask(x: $0, y: 1) == 0 })
  }

  // Hypothesis: zero-radius ellipse handling loses the inclusive endpoints of a thin axis.
  @Test func setA286CollapsedEllipseRetainsItsFullVerticalDiameter() {
    var ellipse = CanvasGridBuffer(size: .init(width: 2, height: 2), grid: .braille2x4)
    ellipse.fillEllipse(centerX: 1, centerY: 3, radiusX: 0, radiusY: 3)
    var diameter = CanvasGridBuffer(size: .init(width: 2, height: 2), grid: .braille2x4)
    for y in 0...6 { diameter.setPixel(x: 1, y: y) }
    #expect(ellipse == diameter)
    #expect(ellipse.mask(x: 0, y: 1) != 0)
  }

  // Hypothesis: a line entering from offscreen restarts its slope at the viewport origin.
  @Test func setA287OffscreenLinePreservesSlopeAndEndpoint() {
    var line = CanvasGridBuffer(size: .init(width: 3, height: 2), grid: .quadrant2x2)
    line.line(from: (x: -2, y: -1), to: (x: 2, y: 3))
    var expected = CanvasGridBuffer(size: .init(width: 3, height: 2), grid: .quadrant2x2)
    expected.setPixel(x: 0, y: 1)
    expected.setPixel(x: 1, y: 2)
    expected.setPixel(x: 2, y: 3)
    #expect(line == expected)
  }

  // Hypothesis: copied canvas buffers share a mutable row after independent clears and fills.
  @Test func setA288CanvasCopyMutationCannotChangeRetainedFrameSamples() {
    var original = CanvasGridBuffer(size: .init(width: 2, height: 2), grid: .fullCell)
    original.setPixel(x: 0, y: 0)
    var next = original
    next.clearPixel(x: 0, y: 0)
    next.fillRect(x: 0, y: 1, width: 2, height: 1)
    #expect(original.character(x: 0, y: 0) == "█")
    #expect(original.mask(x: 1, y: 1) == 0)
    #expect(next.mask(x: 0, y: 0) == 0)
    #expect(next.character(x: 1, y: 1) == "█")
  }

  // Hypothesis: sextant legacy-codepoint gaps alias two distinct coverage masks.
  @Test func setA289EverySextantCoverageHasADistinctGlyph() {
    var glyphs = Set<Character?>()
    for mask in 0..<64 {
      var buffer = CanvasGridBuffer(size: .init(width: 1, height: 1), grid: .sextant2x3)
      for bit in 0..<6 where mask & (1 << bit) != 0 {
        buffer.setPixel(x: bit % 2, y: bit / 2)
      }
      glyphs.insert(buffer.character(x: 0, y: 0))
    }
    #expect(glyphs.count == 64)
  }

  // Hypothesis: clearing direct-cell content incorrectly erases the independent sample layer.
  @Test func setA290DirectCellClearKeepsSampleCoverageAndStyle() {
    var context = canvasContext(.quadrant2x2)
    context.fillCell(.blue, at: .zero)
    context.setPixel(at: .zero, foreground: .red)
    context.clearCell(at: .zero)
    #expect(context.directCells[0][0] == nil)
    #expect(context.canvas.character(x: 0, y: 0) == "▘")
    #expect(context.gridCellStyles[0][0]?.foregroundColor == .red)
  }

  private func canvasContext(_ grid: CanvasGrid) -> CanvasContext {
    CanvasContext(
      canvas: CanvasGridBuffer(size: .init(width: 2, height: 2), grid: grid),
      foreground: .white, background: nil)
  }
}
