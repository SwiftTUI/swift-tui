import Testing

@testable import SwiftTUICore

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
    #expect(CanvasGrid.pixelExact.subdivisionsX == 1)
    #expect(CanvasGrid.pixelExact.subdivisionsY == 1)
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
    #expect(context.gridPoint(for: Point(x: 1.75, y: 0.25)) == CellPoint(x: 3, y: 0))
    #expect(context.gridPoint(for: pointer) == CellPoint(x: 3, y: 0))
  }
}
