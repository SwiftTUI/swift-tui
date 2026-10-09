import Testing

@testable import SwiftTUICore

/// Checks the visible output of clipped text without an alternate rasterizer path.
@Suite("Text raster clipping")
struct TextRasterClippingTests {
  /// Scrolling and horizontal clipping must preserve the original line positions.
  /// - Parameters:
  ///   - family: Text painter used to produce the numbered lines.
  ///   - variation: Vertical origin and the expected visible rows, including empty rows.
  @Test(
    "clipped text retains its original line and column positions",
    arguments: TextPaintFamily.allCases,
    [
      (-5, ["", " 6XYZ", " 7XYZ", " 8XYZ", " 9XYZ", " 10XYZ", " 11XYZ", "", ""]),
      (0, ["", " 1XYZ", " 2XYZ", " 3XYZ", " 4XYZ", " 5XYZ", " 6XYZ", "", ""]),
      (3, ["", "", "", " 0XYZ", " 1XYZ", " 2XYZ", " 3XYZ", "", ""]),
    ])
  func visiblePositions(family: TextPaintFamily, variation: (Int, [String])) {
    let (originY, expectedRows) = variation
    let size = CellSize(width: 18, height: 9)
    let bounds = CellRect(origin: .init(x: -2, y: originY), size: .init(width: 24, height: 20))
    let clip = CellRect(origin: .init(x: 1, y: 1), size: .init(width: 12, height: 6))
    let node = DrawNode(
      identity: testIdentity("clipped-text"), bounds: bounds, clipBounds: clip,
      commands: [family.command(bounds: bounds, lines: (0..<20).map { "abc\($0)XYZ" })])
    let result = Rasterizer().rasterizeCollectingVisibleIdentities(
      node, minimumSize: size, previousSurface: nil, damage: nil)

    #expect(result.surface.lines == expectedRows)
    #expect(result.visibleIdentities == [node.identity])
    for (y, row) in expectedRows.enumerated() where !row.isEmpty {
      #expect(result.surface.cells[y][1].style == family.expectedStyle)
      #expect(result.surface.cells[y][1].hyperlink == family.expectedHyperlink)
    }
    #expect(result.surface.presentationLayers.count == expectedRows.filter { !$0.isEmpty }.count)
    for layer in result.surface.presentationLayers {
      #expect(layer.bounds.origin.x == 1)
      #expect(layer.bounds.size.height == 1)
      #expect((1..<7).contains(layer.bounds.origin.y))
    }
  }

  /// Only the middle eight lines of a tall block belong in the clipped viewport.
  /// - Parameter family: Painter used for the two-thousand-line payload.
  @Test(
    "a scrolled two-thousand-line block shows the correct eight lines",
    arguments: TextPaintFamily.allCases)
  func tallTextOutput(family: TextPaintFamily) {
    let bounds = CellRect(origin: .init(x: 0, y: -1_000), size: .init(width: 24, height: 2_000))
    let clip = CellRect(origin: .zero, size: .init(width: 16, height: 8))
    let node = DrawNode(
      identity: testIdentity("tall-text"), bounds: bounds, clipBounds: clip,
      commands: [family.command(bounds: bounds, lines: (0..<2_000).map { "row \($0)" })])
    let surface = Rasterizer().rasterize(node, minimumSize: clip.size)
    #expect(surface.size == clip.size)
    #expect(surface.lines == (1_000..<1_008).map { "row \($0)" })
    #expect(surface.presentationLayers.count == 8)
  }

  /// Repainting separate damaged rows must preserve clean rows and translucent styles.
  /// - Parameter family: Painter used for the changed, partially visible text block.
  @Test(
    "incremental clipping agrees with fresh output for disjoint damaged rows",
    arguments: TextPaintFamily.allCases)
  func disjointDamage(family: TextPaintFamily) {
    let size = CellSize(width: 18, height: 9)
    let bounds = CellRect(origin: .init(x: 0, y: -5), size: .init(width: 24, height: 20))
    let clip = CellRect(origin: .init(x: 1, y: 1), size: .init(width: 12, height: 6))
    let style = TextStyle(foregroundStyle: .color(.cyan), opacity: 0.65)
    var lines = (0..<20).map { "row \($0)" }
    var node = DrawNode(
      identity: testIdentity("damage-text"), bounds: bounds, clipBounds: clip,
      commands: [family.command(bounds: bounds, lines: lines, style: style)])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previous = rasterizer.rasterize(node, minimumSize: size)
    lines[6] = "new 6"
    lines[10] = "new 10"
    node.commands = [family.command(bounds: bounds, lines: lines, style: style)]
    let fresh = rasterizer.rasterize(node, minimumSize: size)
    let incremental = rasterizer.rasterizeCollectingVisibleIdentities(
      node, minimumSize: size, previousSurface: previous, damage: .init(dirtyRows: [1, 5]))
    #expect(incremental.path == .incremental)
    #expect(incremental.incrementalMismatch == nil)
    #expect(incremental.surface == fresh)
    #expect(incremental.surface.cells[2] == previous.cells[2])
    #expect(incremental.surface.lines[1] == " ew 6")
    #expect(incremental.surface.lines[5] == " ew 10")
  }

  /// Damage outside the text clip must leave its previously painted cells unchanged.
  @Test("damage beyond the text clip preserves the surface")
  func clippedDamagePreservesSurface() {
    let bounds = CellRect(origin: .zero, size: .init(width: 24, height: 2_000))
    let clip = CellRect(origin: .zero, size: .init(width: 16, height: 8))
    let node = DrawNode(
      identity: testIdentity("damage-clip"), bounds: bounds, clipBounds: clip,
      commands: [
        TextPaintFamily.plain.command(bounds: bounds, lines: (0..<2_000).map { "row \($0)" })
      ])
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let previous = rasterizer.rasterize(node, minimumSize: .init(width: 24, height: 10))
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      node, minimumSize: previous.size, previousSurface: previous, damage: .init(dirtyRows: [9]))
    #expect(result.surface == previous)
  }

  /// Wide and combining characters retain their cell spans, styles, and hyperlinks.
  /// - Parameter family: Painter used for the mixed-width line.
  @Test(
    "clipping preserves wide and combining character cells", arguments: TextPaintFamily.allCases)
  func unicodeCells(family: TextPaintFamily) {
    let size = CellSize(width: 6, height: 1)
    let bounds = CellRect(origin: .zero, size: .init(width: 12, height: 1))
    let clip = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 4, height: 1))
    let node = DrawNode(
      identity: testIdentity("unicode-text"), bounds: bounds, clipBounds: clip,
      commands: [family.command(bounds: bounds, lines: ["a界 é xyz"])])
    let surface = Rasterizer().rasterize(node, minimumSize: size)
    #expect(
      surface.cells[0] == [
        .empty,
        .init(
          character: "界", spanWidth: 2, style: family.expectedStyle,
          hyperlink: family.expectedHyperlink),
        .init(
          character: " ", spanWidth: 0, continuationLeadX: 1, style: family.expectedStyle,
          hyperlink: family.expectedHyperlink),
        .init(character: " ", style: family.expectedStyle, hyperlink: family.expectedHyperlink),
        .init(character: "é", style: family.expectedStyle, hyperlink: family.expectedHyperlink),
        .empty,
      ])
    #expect(surface.presentationLayers.map(\.bounds) == [clip])
  }

  /// A preformatted trailing zero-width character still occupies its right-edge cell.
  @Test("zero-width text at a preformatted boundary survives early rejection")
  func zeroWidthAtRightEdge() {
    let size = CellSize(width: 8, height: 1)
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let clip = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 1, height: 1))
    let node = DrawNode(
      identity: testIdentity("zero-width"), bounds: .init(origin: .zero, size: size),
      clipBounds: clip,
      commands: [.preformattedText(bounds: bounds, lines: ["A\u{200B}"], style: .init())])
    let surface = Rasterizer().rasterize(node, minimumSize: size)
    #expect(surface.cells[0][0] == .empty)
    #expect(surface.cells[0][1].character == "\u{200B}")
    #expect(surface.cells[0][1].spanWidth == 1)
    #expect(surface.presentationLayers.map(\.bounds) == [clip])
  }

  /// An explicit clip needs the full character span; a surface edge only needs its lead cell.
  @Test("explicit clip and surface edge retain different wide-glyph rules")
  func wideGlyphEligibility() {
    let rasterizer = Rasterizer()
    let size = CellSize(width: 4, height: 1)
    let clip = CellRect(origin: .zero, size: size)
    #expect(rasterizer.textGlyphCanWrite(atX: 3, y: 0, width: 2, clip: nil, surfaceSize: size))
    #expect(!rasterizer.textGlyphCanWrite(atX: 3, y: 0, width: 2, clip: clip, surfaceSize: size))
    #expect(!rasterizer.textGlyphCanWrite(atX: -1, y: 0, width: 2, clip: nil, surfaceSize: size))
    #expect(rasterizer.textGlyphCanWrite(atX: 3, y: 0, width: 0, clip: clip, surfaceSize: size))
  }
}

/// Produces text fixtures through each supported text painter.
enum TextPaintFamily: CaseIterable, Sendable {
  /// Wrapped ordinary text.
  case plain
  /// Explicit unwrapped lines.
  case preformatted
  /// Explicit lines with bold styled runs.
  case styled
  /// Wrapped text carrying a hyperlink.
  case rich

  /// The complete style expected from an opaque cyan fixture.
  var expectedStyle: ResolvedTextStyle {
    .init(foregroundColor: .cyan, emphasis: self == .styled ? .bold : [])
  }

  /// The fixture's link destination, present only for rich text.
  var expectedHyperlink: String? {
    self == .rich ? "https://example.com/text" : nil
  }

  /// Builds a text command without changing the fixture's original bounds.
  /// - Parameters:
  ///   - bounds: Absolute layout and color-sampling bounds.
  ///   - lines: Source lines whose positions the test checks.
  ///   - style: Base style; the styled painter additionally applies bold emphasis.
  /// - Returns: A command for this family's normal production painter.
  func command(
    bounds: CellRect, lines: [String],
    style: TextStyle = .init(foregroundStyle: .color(.cyan))
  ) -> DrawCommand {
    switch self {
    case .plain:
      return .text(
        bounds: bounds, content: lines.joined(separator: "\n"), style: style,
        lineLimit: nil, truncationMode: .tail, wrappingStrategy: .wordBoundary)
    case .preformatted:
      return .preformattedText(bounds: bounds, lines: lines, style: style)
    case .styled:
      return .styledPreformattedText(
        bounds: bounds,
        lines: lines.map { .init(runs: [.init(content: $0, style: .init(emphasis: .bold))]) },
        style: style)
    case .rich:
      return .richText(
        bounds: bounds,
        payload: .init(runs: [
          .init(
            text: lines.joined(separator: "\n"), style: style,
            destination: "https://example.com/text")
        ]),
        lineLimit: nil, truncationMode: .tail, wrappingStrategy: .wordBoundary)
    }
  }
}
