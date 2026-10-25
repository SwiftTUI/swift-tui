import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("CanvasGrid")
struct CanvasGridTests {
  @Test("CanvasGrid styles report their in-cell subdivisions")
  func subdivisions() {
    #expect(CanvasGrid.braille2x4.subdivisionsX == 2)
    #expect(CanvasGrid.braille2x4.subdivisionsY == 4)
    #expect(CanvasGrid.octant2x4.subdivisionsX == 2)
    #expect(CanvasGrid.octant2x4.subdivisionsY == 4)
    #expect(CanvasGrid.sextant2x3.subdivisionsX == 2)
    #expect(CanvasGrid.sextant2x3.subdivisionsY == 3)
    #expect(CanvasGrid.quadrant2x2.subdivisionsX == 2)
    #expect(CanvasGrid.quadrant2x2.subdivisionsY == 2)
    #expect(CanvasGrid.verticalHalfBlock.subdivisionsX == 1)
    #expect(CanvasGrid.verticalHalfBlock.subdivisionsY == 2)
    #expect(CanvasGrid.horizontalHalfBlock.subdivisionsX == 2)
    #expect(CanvasGrid.horizontalHalfBlock.subdivisionsY == 1)
    #expect(CanvasGrid.fullCell.subdivisionsX == 1)
    #expect(CanvasGrid.fullCell.subdivisionsY == 1)
  }

  @Test("CanvasGridBuffer preserves Braille masks for the default grid")
  func brailleGlyph() {
    var buffer = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .braille2x4)

    buffer.setPixel(x: 0, y: 0)
    buffer.setPixel(x: 1, y: 3)

    let scalar = buffer.character(x: 0, y: 0)?.unicodeScalars.first?.value ?? 0
    #expect(scalar == 0x2800 + 0x81)
  }

  @Test("CanvasGridBuffer packs quadrant block masks")
  func quadrantGlyph() {
    var buffer = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .quadrant2x2)

    buffer.setPixel(x: 0, y: 0)
    buffer.setPixel(x: 1, y: 1)

    #expect(buffer.character(x: 0, y: 0) == "▚")
  }

  @Test("CanvasGridBuffer packs vertical half blocks")
  func verticalHalfBlockGlyphs() {
    var top = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .verticalHalfBlock)
    top.setPixel(x: 0, y: 0)

    var bottom = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .verticalHalfBlock)
    bottom.setPixel(x: 0, y: 1)

    var full = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .verticalHalfBlock)
    full.setPixel(x: 0, y: 0)
    full.setPixel(x: 0, y: 1)

    #expect(top.character(x: 0, y: 0) == "▀")
    #expect(bottom.character(x: 0, y: 0) == "▄")
    #expect(full.character(x: 0, y: 0) == "█")
  }

  @Test("CanvasGridBuffer packs horizontal half blocks")
  func horizontalHalfBlockGlyphs() {
    var left = CanvasGridBuffer(
      size: CellSize(width: 1, height: 1),
      grid: .horizontalHalfBlock
    )
    left.setPixel(x: 0, y: 0)

    var right = CanvasGridBuffer(
      size: CellSize(width: 1, height: 1),
      grid: .horizontalHalfBlock
    )
    right.setPixel(x: 1, y: 0)

    var full = CanvasGridBuffer(
      size: CellSize(width: 1, height: 1),
      grid: .horizontalHalfBlock
    )
    full.setPixel(x: 0, y: 0)
    full.setPixel(x: 1, y: 0)

    #expect(left.character(x: 0, y: 0) == "▌")
    #expect(right.character(x: 0, y: 0) == "▐")
    #expect(full.character(x: 0, y: 0) == "█")
  }

  @Test("CanvasGridBuffer packs full-cell and sextant glyphs")
  func fullCellAndSextantGlyphs() {
    var fullCell = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .fullCell)
    fullCell.setPixel(x: 0, y: 0)
    #expect(fullCell.character(x: 0, y: 0) == "█")

    var sextant = CanvasGridBuffer(size: CellSize(width: 1, height: 1), grid: .sextant2x3)
    sextant.setPixel(x: 0, y: 0)
    #expect(sextant.character(x: 0, y: 0) == Character(UnicodeScalar(0x1FB00)!))

    sextant.setPixel(x: 0, y: 1)
    sextant.setPixel(x: 0, y: 2)
    #expect(sextant.character(x: 0, y: 0) == "▌")
  }

  @Test("CanvasContext projects continuous cell coordinates into the active grid")
  func contextGridPointProjection() {
    let context = CanvasContext(
      canvas: CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .quadrant2x2),
      foreground: .white,
      background: nil
    )
    let pointer = PointerLocation.subCell(
      location: Point(x: 1.75, y: 0.25),
      source: .nativePixels,
      metrics: CellPixelMetrics(width: 10, height: 20, source: .reported)
    )

    #expect(context.size == CellSize(width: 4, height: 2))
    #expect(context.gridSample(for: Point(x: 1.75, y: 0.25)) == GridSample(x: 3, y: 0))
    #expect(context.gridSample(for: pointer) == GridSample(x: 3, y: 0))
  }

  // MARK: - Bounded continuous and grid primitives (STUI-753)

  @Test("CanvasContext draws nothing for non-finite geometry, without trapping")
  func contextNonFiniteGeometryDrawsNothing() async {
    await #expect(processExitsWith: .success) {
      var context = brailleGridContext()
      context.strokeEllipse(center: Point(x: 1, y: 1), radiusX: .infinity, radiusY: 1)
      context.strokeCircle(center: Point(x: 1, y: 1), radius: -.infinity)
      context.line(from: Point(x: .nan, y: 0), to: Point(x: 1, y: 1))
      context.line(from: Point(x: 0, y: 0), to: Point(x: .infinity, y: 1))
      context.fillEllipse(center: Point(x: 1, y: 1), radiusX: .nan, radiusY: 1)
      #expect(litGridSamples(context.canvas).isEmpty)
    }
  }

  @Test("CanvasContext treats a NaN radius as unusable instead of a one-sample dot")
  func contextNaNRadiusDrawsNothing() {
    var context = brailleGridContext()
    context.strokeCircle(center: Point(x: 1, y: 1), radius: .nan)
    context.strokeEllipse(center: Point(x: 1, y: 1), radiusX: .nan, radiusY: 1)
    #expect(litGridSamples(context.canvas).isEmpty)
  }

  @Test("CanvasContext huge finite geometry costs the buffer and keeps its direction")
  func contextHugeFiniteGeometryIsBounded() {
    var line = brailleGridContext()
    line.line(from: Point(x: 0, y: 0.1), to: Point(x: 1e300, y: 0.1))
    #expect(litGridSamples(line.canvas) == clippedRasterPixels((0..<8).map { ($0, 0) }))
    var vertical = brailleGridContext()
    vertical.line(from: Point(x: 1.25, y: -1e300), to: Point(x: 1.25, y: 1e300))
    #expect(litGridSamples(vertical.canvas) == clippedRasterPixels((0..<8).map { (2, $0) }))
    let everything = Rect(
      origin: Point(x: -1e300, y: -1e300), size: Size(width: 2e300, height: 2e300))
    var stroked = brailleGridContext()
    stroked.strokeRect(everything)
    #expect(litGridSamples(stroked.canvas).isEmpty)
    var filled = brailleGridContext()
    filled.fillRect(everything)
    #expect(litGridSamples(filled.canvas).count == 64)
    var flat = brailleGridContext()
    flat.fillEllipse(center: .zero, radiusX: 1e300, radiusY: 0)
    #expect(litGridSamples(flat.canvas) == clippedRasterPixels((0..<8).map { ($0, 0) }))
  }

  @Test("CanvasGridBuffer primitives that overhang the buffer match the unclipped walks")
  func gridPrimitivesMatchReference() {
    var random = ClippedRasterReference.Random(state: 0xC0FF_EE11)
    func fresh() -> CanvasGridBuffer {
      CanvasGridBuffer(size: CellSize(width: 3, height: 2), grid: .braille2x4)
    }
    for index in 0..<800 {
      let span = index < 50 ? -1_000...1_000 : -14...22
      let start = (x: random.next(span), y: random.next(span))
      let end = (x: random.next(span), y: random.next(span))
      var buffer = fresh()
      var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
      buffer.line(from: start, to: end)
      reference.line(from: start, to: end)
      #expect(litGridSamples(buffer) == reference.pixels, "line \(start) \(end)")
    }
    for _ in 0..<300 {
      let x = random.next(-14...20)
      let y = random.next(-14...22)
      let width = random.next(-2...24)
      let height = random.next(-2...24)
      var buffer = fresh()
      var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
      buffer.strokeRect(x: x, y: y, width: width, height: height)
      reference.strokeRect(x: x, y: y, width: width, height: height)
      #expect(litGridSamples(buffer) == reference.pixels, "strokeRect \(x) \(y) \(width) \(height)")
      buffer = fresh()
      reference = ClippedRasterReference.Buffer(width: 6, height: 8)
      buffer.fillRect(x: x, y: y, width: width, height: height)
      reference.fillRect(x: x, y: y, width: width, height: height)
      #expect(litGridSamples(buffer) == reference.pixels, "fillRect \(x) \(y) \(width) \(height)")
    }
    for _ in 0..<300 {
      let cx = random.next(-14...20)
      let cy = random.next(-14...22)
      let rx = random.next(-1...16)
      let ry = random.next(-1...16)
      var buffer = fresh()
      var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
      buffer.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      reference.gridStrokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      #expect(litGridSamples(buffer) == reference.pixels, "strokeEllipse \(cx) \(cy) \(rx) \(ry)")
      buffer = fresh()
      reference = ClippedRasterReference.Buffer(width: 6, height: 8)
      buffer.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      reference.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
      #expect(litGridSamples(buffer) == reference.pixels, "fillEllipse \(cx) \(cy) \(rx) \(ry)")
    }
  }
}

/// A 4 x 2 cell Braille context: 8 x 8 grid samples.
private func brailleGridContext() -> CanvasContext {
  CanvasContext(
    canvas: CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4),
    foreground: .white,
    background: nil
  )
}

/// The lit samples of a Braille-grid buffer.
private func litGridSamples(_ buffer: CanvasGridBuffer) -> Set<ClippedRasterPixel> {
  var lit: Set<ClippedRasterPixel> = []
  for y in 0..<buffer.pixelHeight {
    for x in 0..<buffer.pixelWidth {
      let bit = UInt16(BrailleCell.bitMask(x: x % 2, y: y % 4) ?? 0)
      if buffer.mask(x: x / 2, y: y / 4) & bit != 0 {
        lit.insert(ClippedRasterPixel(x: x, y: y))
      }
    }
  }
  return lit
}
