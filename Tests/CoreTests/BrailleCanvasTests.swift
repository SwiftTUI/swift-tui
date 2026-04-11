import Testing

@testable import Core

// MARK: - BrailleCell

@Test("BrailleCell empty mask yields U+2800")
func brailleCellEmpty() {
  let cell = BrailleCell()
  #expect(cell.glyph == "\u{2800}")
  #expect(cell.mask == 0)
}

@Test("BrailleCell all 8 dots set yields ⣿")
func brailleCellAllDots() {
  var cell = BrailleCell()
  for x in 0..<2 {
    for y in 0..<4 {
      cell.set(x: x, y: y)
    }
  }
  #expect(cell.glyph == "⣿")
  #expect(cell.mask == 0xFF)
}

@Test("BrailleCell top-left dot yields ⠁")
func brailleCellTopLeftDot() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 0)
  #expect(cell.glyph == "⠁")
}

@Test("BrailleCell top-right dot yields ⠈")
func brailleCellTopRightDot() {
  var cell = BrailleCell()
  cell.set(x: 1, y: 0)
  #expect(cell.glyph == "⠈")
  #expect(cell.mask == 0x08)
}

@Test("BrailleCell bottom dots use 0x40 / 0x80")
func brailleCellBottomDots() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 3)
  #expect(cell.mask == 0x40)
  cell.set(x: 1, y: 3)
  #expect(cell.mask == 0xC0)
}

@Test("BrailleCell clear removes a dot")
func brailleCellClear() {
  var cell = BrailleCell()
  cell.set(x: 0, y: 0)
  cell.set(x: 1, y: 0)
  cell.clear(x: 0, y: 0)
  #expect(cell.mask == 0x08)
  #expect(cell.contains(x: 0, y: 0) == false)
  #expect(cell.contains(x: 1, y: 0) == true)
}

@Test("BrailleCell out-of-range coordinates are ignored")
func brailleCellOutOfRange() {
  var cell = BrailleCell()
  cell.set(x: 2, y: 0)
  cell.set(x: 0, y: 4)
  cell.set(x: -1, y: 0)
  #expect(cell.mask == 0)
}

// MARK: - BrailleCanvas

@Test("BrailleCanvas dimensions convert cells to subpixels")
func brailleCanvasDimensions() {
  let canvas = BrailleCanvas(width: 3, height: 2)
  #expect(canvas.width == 3)
  #expect(canvas.height == 2)
  #expect(canvas.subpixelWidth == 6)
  #expect(canvas.subpixelHeight == 8)
}

@Test("BrailleCanvas setPixel places a dot in the correct cell")
func brailleCanvasSetPixel() {
  var canvas = BrailleCanvas(width: 2, height: 1)
  canvas.setPixel(x: 0, y: 0)  // cell (0,0) dot (0,0)
  #expect(canvas.cell(x: 0, y: 0).mask == 0x01)

  canvas.setPixel(x: 3, y: 3)  // cell (1,0) dot (1,3) → 0x80
  #expect(canvas.cell(x: 1, y: 0).mask == 0x80)
}

@Test("BrailleCanvas horizontal line sets the top row of every cell")
func brailleCanvasHorizontalLine() {
  var canvas = BrailleCanvas(width: 2, height: 1)  // 4×4 subpixels
  canvas.line(from: (x: 0, y: 0), to: (x: 3, y: 0))
  // Cell (0,0): dots at (0,0) and (1,0) → 0x01 | 0x08 = 0x09 → ⠉
  #expect(canvas.cell(x: 0, y: 0).glyph == "⠉")
  #expect(canvas.cell(x: 1, y: 0).glyph == "⠉")
}

@Test("BrailleCanvas vertical line sets the leftmost column")
func brailleCanvasVerticalLine() {
  var canvas = BrailleCanvas(width: 1, height: 1)  // 2×4 subpixels
  canvas.line(from: (x: 0, y: 0), to: (x: 0, y: 3))
  // All four dots of left column: 0x01 | 0x02 | 0x04 | 0x40 = 0x47 → ⡇
  #expect(canvas.cell(x: 0, y: 0).glyph == "⡇")
}

@Test("BrailleCanvas diagonal line covers each subpixel along the way")
func brailleCanvasDiagonalLine() {
  var canvas = BrailleCanvas(width: 1, height: 1)
  canvas.line(from: (x: 0, y: 0), to: (x: 1, y: 3))
  // Bresenham visits (0,0), (0,1), (1,2), (1,3) — or similar depending
  // on rounding. The cell should have at least 4 dots set.
  let mask = canvas.cell(x: 0, y: 0).mask
  #expect(mask.nonzeroBitCount >= 4)
}

@Test("BrailleCanvas strokeRect draws four edges")
func brailleCanvasStrokeRect() {
  var canvas = BrailleCanvas(width: 2, height: 1)  // 4×4 subpixels
  canvas.strokeRect(x: 0, y: 0, width: 4, height: 4)
  // Every cell should have the outer dots set. Cell (0,0) is the
  // top-left quadrant: dots (0,0), (0,1), (0,2), (0,3), (1,0) are set.
  let tl = canvas.cell(x: 0, y: 0).mask
  #expect(tl & 0x01 != 0)  // top-left dot
  #expect(tl & 0x08 != 0)  // top row, right column
  #expect(tl & 0x02 != 0)  // left column, y=1
  #expect(tl & 0x40 != 0)  // left column, y=3
}

@Test("BrailleCanvas fillRect fills every subpixel inside")
func brailleCanvasFillRect() {
  var canvas = BrailleCanvas(width: 1, height: 1)
  canvas.fillRect(x: 0, y: 0, width: 2, height: 4)
  // Every dot in cell (0,0) should be set → ⣿
  #expect(canvas.cell(x: 0, y: 0).glyph == "⣿")
}

@Test("BrailleCanvas strokeCircle with radius 0 sets a single pixel")
func brailleCanvasStrokeCircleZero() {
  var canvas = BrailleCanvas(width: 1, height: 1)
  canvas.strokeCircle(centerX: 1, centerY: 2, radius: 0)
  // (1, 2) → cell (0,0), dot (1,2) → 0x20
  #expect(canvas.cell(x: 0, y: 0).mask == 0x20)
}

@Test("BrailleCanvas strokeCircle with radius 4 produces a closed ring")
func brailleCanvasStrokeCircle() {
  var canvas = BrailleCanvas(width: 5, height: 3)  // 10×12 subpixels
  canvas.strokeCircle(centerX: 5, centerY: 6, radius: 4)
  // At least the four cardinal points should be set.
  // Top cardinal: (5, 2) → cell (2, 0), dot (1, 2) → 0x20
  // Right cardinal: (9, 6) → cell (4, 1), dot (1, 2) → 0x20
  // Bottom cardinal: (5, 10) → cell (2, 2), dot (1, 2) → 0x20
  // Left cardinal: (1, 6) → cell (0, 1), dot (1, 2) → 0x20
  #expect(canvas.cell(x: 2, y: 0).mask & 0x20 != 0)
  #expect(canvas.cell(x: 4, y: 1).mask & 0x20 != 0)
  #expect(canvas.cell(x: 2, y: 2).mask & 0x20 != 0)
  #expect(canvas.cell(x: 0, y: 1).mask & 0x20 != 0)
}

@Test("BrailleCanvas fillCircle sets the center")
func brailleCanvasFillCircleCenter() {
  var canvas = BrailleCanvas(width: 5, height: 3)
  canvas.fillCircle(centerX: 5, centerY: 6, radius: 3)
  // Center (5, 6) → cell (2, 1), dot (1, 2) → 0x20
  #expect(canvas.cell(x: 2, y: 1).mask & 0x20 != 0)
}

@Test("BrailleCanvas out-of-range pixels are silently dropped")
func brailleCanvasClipping() {
  var canvas = BrailleCanvas(width: 1, height: 1)  // 2×4 subpixels
  canvas.setPixel(x: -1, y: 0)
  canvas.setPixel(x: 2, y: 0)
  canvas.setPixel(x: 0, y: 4)
  canvas.setPixel(x: 0, y: -1)
  #expect(canvas.cell(x: 0, y: 0).mask == 0)
}

@Test("BrailleCanvas out-of-range cell query returns empty cell")
func brailleCanvasCellOutOfRange() {
  let canvas = BrailleCanvas(width: 2, height: 2)
  #expect(canvas.cell(x: -1, y: 0).mask == 0)
  #expect(canvas.cell(x: 0, y: -1).mask == 0)
  #expect(canvas.cell(x: 2, y: 0).mask == 0)
  #expect(canvas.cell(x: 0, y: 2).mask == 0)
}
