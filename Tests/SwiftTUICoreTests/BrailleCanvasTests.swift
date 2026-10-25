import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

#if canImport(Darwin)
  import Darwin
#elseif canImport(Glibc)
  import Glibc
#elseif canImport(Android)
  import Android
#elseif canImport(Musl)
  import Musl
#elseif canImport(ucrt)
  import ucrt
#endif

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

@Test("BrailleCanvas fillEllipse zero radii sets only the center pixel")
func brailleCanvasFillEllipseZero() {
  var canvas = BrailleCanvas(width: 1, height: 1)
  canvas.fillEllipse(centerX: 1, centerY: 2, radiusX: 0, radiusY: 0)
  // (1, 2) → cell (0, 0), dot (1, 2) → 0x20
  #expect(canvas.cell(x: 0, y: 0).mask == 0x20)
}

@Test("BrailleCanvas fillEllipse fills cardinal points and center")
func brailleCanvasFillEllipseCardinal() {
  var canvas = BrailleCanvas(width: 6, height: 3)  // 12×12 subpixels
  canvas.fillEllipse(centerX: 6, centerY: 6, radiusX: 5, radiusY: 4)
  // Center pixel must be set.
  let centerCell = canvas.cell(x: 3, y: 1)
  #expect(centerCell.mask & 0x20 != 0)  // dot (1, 2) at (6, 6)
  // Horizontal extremes: (1, 6) and (11, 6) — inside rx=5.
  // (1, 6) → cell (0, 1) dot (1, 2) → 0x20
  #expect(canvas.cell(x: 0, y: 1).mask & 0x20 != 0)
  // (11, 6) → cell (5, 1) dot (1, 2) → 0x20
  #expect(canvas.cell(x: 5, y: 1).mask & 0x20 != 0)
  // Vertical extremes: (6, 2) and (6, 10) — inside ry=4.
  // (6, 2) → cell (3, 0) dot (0, 2) → 0x04
  #expect(canvas.cell(x: 3, y: 0).mask & 0x04 != 0)
  // (6, 10) → cell (3, 2) dot (0, 2) → 0x04
  #expect(canvas.cell(x: 3, y: 2).mask & 0x04 != 0)
}

@Test("BrailleCanvas strokeEllipse draws cardinal points but leaves center blank")
func brailleCanvasStrokeEllipse() {
  var canvas = BrailleCanvas(width: 6, height: 3)  // 12×12 subpixels
  canvas.strokeEllipse(centerX: 6, centerY: 6, radiusX: 5, radiusY: 4)
  // Center pixel must NOT be set.
  let centerCell = canvas.cell(x: 3, y: 1)
  #expect(centerCell.mask & 0x20 == 0)
  // The four cardinal extremes should land on the outline.
  // Leftmost: (1, 6) → cell (0, 1) dot (1, 2) → 0x20
  #expect(canvas.cell(x: 0, y: 1).mask & 0x20 != 0)
  // Rightmost: (11, 6) → cell (5, 1) dot (1, 2) → 0x20
  #expect(canvas.cell(x: 5, y: 1).mask & 0x20 != 0)
  // Top: (6, 2) → cell (3, 0) dot (0, 2) → 0x04
  #expect(canvas.cell(x: 3, y: 0).mask & 0x04 != 0)
  // Bottom: (6, 10) → cell (3, 2) dot (0, 2) → 0x04
  #expect(canvas.cell(x: 3, y: 2).mask & 0x04 != 0)
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

// MARK: - Bounded integer primitives (STUI-741, STUI-753)

/// A lit subpixel or grid sample, for set comparisons.
struct ClippedRasterPixel: Hashable, CustomStringConvertible {
  var x: Int
  var y: Int

  var description: String { "(\(x), \(y))" }
}

func litBraillePixels(_ canvas: BrailleCanvas) -> Set<ClippedRasterPixel> {
  var lit: Set<ClippedRasterPixel> = []
  for y in 0..<canvas.subpixelHeight {
    for x in 0..<canvas.subpixelWidth
    where canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) {
      lit.insert(ClippedRasterPixel(x: x, y: y))
    }
  }
  return lit
}

func clippedRasterPixels(_ points: [(Int, Int)]) -> Set<ClippedRasterPixel> {
  Set(points.map { ClippedRasterPixel(x: $0.0, y: $0.1) })
}

/// The integer primitives exactly as they were written before clipping moved
/// ahead of iteration: every loop walks the whole shape and `plot` clips each
/// sample. Used only with small coordinates, where none of it can overflow.
enum ClippedRasterReference {
  struct Buffer {
    let width: Int
    let height: Int
    var pixels: Set<ClippedRasterPixel> = []

    init(width: Int, height: Int) {
      self.width = width
      self.height = height
    }

    mutating func plot(_ x: Int, _ y: Int) {
      if x >= 0, x < width, y >= 0, y < height { pixels.insert(ClippedRasterPixel(x: x, y: y)) }
    }

    mutating func line(from: (x: Int, y: Int), to: (x: Int, y: Int)) {
      var x0 = from.x
      var y0 = from.y
      let x1 = to.x
      let y1 = to.y
      let dx = abs(x1 - x0)
      let sx = x0 < x1 ? 1 : -1
      let dy = -abs(y1 - y0)
      let sy = y0 < y1 ? 1 : -1
      var error = dx + dy
      while true {
        plot(x0, y0)
        if x0 == x1, y0 == y1 { break }
        let e2 = 2 * error
        if e2 >= dy {
          if x0 == x1 { break }
          error += dy
          x0 += sx
        }
        if e2 <= dx {
          if y0 == y1 { break }
          error += dx
          y0 += sy
        }
      }
    }

    mutating func strokeRect(x: Int, y: Int, width w: Int, height h: Int) {
      guard w > 0, h > 0 else { return }
      for dx in 0..<w {
        plot(x + dx, y)
        if h > 1 { plot(x + dx, y + h - 1) }
      }
      if h > 2 {
        for dy in 1..<(h - 1) {
          plot(x, y + dy)
          if w > 1 { plot(x + w - 1, y + dy) }
        }
      }
    }

    mutating func fillRect(x: Int, y: Int, width w: Int, height h: Int) {
      guard w > 0, h > 0 else { return }
      for dy in 0..<h {
        for dx in 0..<w { plot(x + dx, y + dy) }
      }
    }

    mutating func strokeCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
      guard radius >= 0 else { return }
      if radius == 0 {
        plot(cx, cy)
        return
      }
      var x = radius
      var y = 0
      var err = 1 - radius
      while x >= y {
        plot(cx + x, cy + y)
        plot(cx + y, cy + x)
        plot(cx - y, cy + x)
        plot(cx - x, cy + y)
        plot(cx - x, cy - y)
        plot(cx - y, cy - x)
        plot(cx + y, cy - x)
        plot(cx + x, cy - y)
        y += 1
        if err < 0 {
          err += 2 * y + 1
        } else {
          x -= 1
          err += 2 * (y - x) + 1
        }
      }
    }

    mutating func fillCircle(centerX cx: Int, centerY cy: Int, radius: Int) {
      guard radius >= 0 else { return }
      let r2 = radius * radius
      for dy in -radius...radius {
        let dx = Int(Double(r2 - dy * dy).squareRoot().rounded(.down))
        for x in (cx - dx)...(cx + dx) { plot(x, cy + dy) }
      }
    }

    mutating func fillEllipse(centerX cx: Int, centerY cy: Int, radiusX rx: Int, radiusY ry: Int) {
      guard rx >= 0, ry >= 0 else { return }
      if rx == 0 && ry == 0 {
        plot(cx, cy)
        return
      }
      if rx == 0 {
        for dy in -ry...ry { plot(cx, cy + dy) }
        return
      }
      if ry == 0 {
        for dx in -rx...rx { plot(cx + dx, cy) }
        return
      }
      for dy in -ry...ry {
        let dxMax = EllipseRasterization.halfSpan(radiusX: rx, radiusY: ry, offsetY: dy)
        for dx in -dxMax...dxMax { plot(cx + dx, cy + dy) }
      }
    }

    /// `BrailleCanvas.strokeEllipse`: axis special cases, at least 32 steps.
    mutating func brailleStrokeEllipse(
      centerX cx: Int, centerY cy: Int, radiusX rx: Int, radiusY ry: Int
    ) {
      guard rx >= 0, ry >= 0 else { return }
      if rx == 0 && ry == 0 {
        plot(cx, cy)
        return
      }
      if rx == 0 {
        for dy in -ry...ry { plot(cx, cy + dy) }
        return
      }
      if ry == 0 {
        for dx in -rx...rx { plot(cx + dx, cy) }
        return
      }
      let steps = max(32, 4 * (rx + ry))
      let twoPi = 2.0 * .pi
      var previous: (x: Int, y: Int)?
      for i in 0...steps {
        let angle = twoPi * Double(i) / Double(steps)
        let x = cx + Int((Double(rx) * cos(angle)).rounded())
        let y = cy + Int((Double(ry) * sin(angle)).rounded())
        if let previous { line(from: previous, to: (x, y)) } else { plot(x, y) }
        previous = (x, y)
      }
    }

    /// `CanvasGridBuffer.strokeEllipse`: no axis special cases, at least 12 steps.
    mutating func gridStrokeEllipse(
      centerX cx: Int, centerY cy: Int, radiusX rx: Int, radiusY ry: Int
    ) {
      guard rx >= 0, ry >= 0 else { return }
      if rx == 0 && ry == 0 {
        plot(cx, cy)
        return
      }
      let steps = max(12, (rx + ry) * 4)
      var previous: (x: Int, y: Int)?
      for step in 0...steps {
        let theta = 2.0 * Double.pi * Double(step) / Double(steps)
        let point = (
          x: cx + Int((Double(rx) * cos(theta)).rounded()),
          y: cy + Int((Double(ry) * sin(theta)).rounded())
        )
        if let previous { line(from: previous, to: point) } else { plot(point.x, point.y) }
        previous = point
      }
    }
  }

  /// A fixed-seed generator, so every run checks the same cases.
  struct Random {
    var state: UInt64

    mutating func next(_ range: ClosedRange<Int>) -> Int {
      state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
      let span = UInt64(range.upperBound - range.lowerBound + 1)
      return range.lowerBound + Int((state >> 33) % span)
    }
  }
}

@Test("BrailleCanvas lines with integer-edge endpoints draw only their in-buffer pixels")
func brailleCanvasExtremeLineEndpoints() async {
  await #expect(processExitsWith: .success) {
    var row = BrailleCanvas(width: 2, height: 2)
    row.line(from: (x: 0, y: 1), to: (x: Int.max, y: 1))
    #expect(litBraillePixels(row) == clippedRasterPixels([(0, 1), (1, 1), (2, 1), (3, 1)]))
    var diagonal = BrailleCanvas(width: 2, height: 2)
    diagonal.line(from: (x: Int.min, y: Int.min), to: (x: Int.max, y: Int.max))
    #expect(litBraillePixels(diagonal) == clippedRasterPixels([(0, 0), (1, 1), (2, 2), (3, 3)]))
  }
}

@Test("BrailleCanvas line cost is bounded by the buffer, not by the endpoint distance")
func brailleCanvasLongLinesAreBounded() {
  var shallow = BrailleCanvas(width: 2, height: 2)
  shallow.line(from: (x: 0, y: 0), to: (x: 1 << 40, y: 1))
  #expect(litBraillePixels(shallow) == clippedRasterPixels([(0, 0), (1, 0), (2, 0), (3, 0)]))
  var steep = BrailleCanvas(width: 2, height: 2)
  steep.line(from: (x: 3, y: -(1 << 40)), to: (x: 3, y: 1 << 40))
  #expect(litBraillePixels(steep) == clippedRasterPixels((0..<8).map { (3, $0) }))
}

@Test("BrailleCanvas rectangles at the integer edges are clipped without trapping")
func brailleCanvasExtremeRectangles() async {
  await #expect(processExitsWith: .success) {
    var canvas = BrailleCanvas(width: 2, height: 2)
    canvas.fillRect(x: Int.max - 1, y: 0, width: 4, height: 1)
    canvas.strokeRect(x: Int.max, y: 0, width: 2, height: 3)
    canvas.strokeRect(x: 0, y: Int.max - 1, width: 3, height: 4)
    #expect(litBraillePixels(canvas).isEmpty)
  }
}

@Test("BrailleCanvas rectangle cost is bounded by the buffer")
func brailleCanvasHugeRectanglesAreBounded() {
  var stroked = BrailleCanvas(width: 2, height: 2)
  stroked.strokeRect(x: -(1 << 40), y: 0, width: 1 << 41, height: 3)
  #expect(litBraillePixels(stroked) == clippedRasterPixels((0..<4).flatMap { [($0, 0), ($0, 2)] }))
  var filled = BrailleCanvas(width: 2, height: 2)
  filled.fillRect(x: -(1 << 40), y: -(1 << 40), width: 1 << 41, height: 1 << 41)
  #expect(litBraillePixels(filled).count == 32)
}

@Test("BrailleCanvas circles with integer-edge radii or centres do not trap")
func brailleCanvasExtremeCircles() async {
  await #expect(processExitsWith: .success) {
    var filled = BrailleCanvas(width: 2, height: 2)
    filled.fillCircle(centerX: 1, centerY: 1, radius: Int.max / 2)
    #expect(litBraillePixels(filled).count == 32)
    var far = BrailleCanvas(width: 2, height: 2)
    far.strokeCircle(centerX: Int.max, centerY: 0, radius: 2)
    far.fillCircle(centerX: Int.min, centerY: 0, radius: 2)
    #expect(litBraillePixels(far).isEmpty)
  }
}

@Test("BrailleCanvas huge circles cost the buffer and draw only their visible arc")
func brailleCanvasHugeCirclesAreBounded() {
  var inside = BrailleCanvas(width: 2, height: 2)
  inside.strokeCircle(centerX: 0, centerY: 0, radius: 1 << 40)
  #expect(litBraillePixels(inside).isEmpty)
  var crossing = BrailleCanvas(width: 2, height: 2)
  crossing.strokeCircle(centerX: 2 - (1 << 40), centerY: 4, radius: 1 << 40)
  #expect(litBraillePixels(crossing) == clippedRasterPixels((0..<8).map { (2, $0) }))
}

@Test("BrailleCanvas ellipses with integer-edge radii or centres do not trap")
func brailleCanvasExtremeEllipses() async {
  await #expect(processExitsWith: .success) {
    var far = BrailleCanvas(width: 2, height: 2)
    far.strokeEllipse(centerX: Int.max, centerY: 0, radiusX: 2, radiusY: 2)
    far.fillEllipse(centerX: Int.max, centerY: 0, radiusX: 2, radiusY: 1)
    far.strokeEllipse(centerX: 0, centerY: Int.min, radiusX: 0, radiusY: 3)
    #expect(litBraillePixels(far).isEmpty)
    // Nearly flat: the visible part of the outline is its lower edge.
    var flat = BrailleCanvas(width: 2, height: 2)
    flat.strokeEllipse(centerX: 0, centerY: 0, radiusX: Int.max / 2, radiusY: 1)
    #expect(litBraillePixels(flat) == clippedRasterPixels([(0, 1), (1, 1), (2, 1), (3, 1)]))
  }
}

@Test("BrailleCanvas huge ellipses cost the buffer")
func brailleCanvasHugeEllipsesAreBounded() {
  var crossing = BrailleCanvas(width: 2, height: 2)
  crossing.strokeEllipse(
    centerX: 2 - (1 << 40), centerY: 4, radiusX: 1 << 40, radiusY: 1 << 40)
  #expect(litBraillePixels(crossing) == clippedRasterPixels((0..<8).map { (2, $0) }))
  var filled = BrailleCanvas(width: 2, height: 2)
  filled.fillEllipse(centerX: 2 - (1 << 40), centerY: 4, radiusX: 1 << 40, radiusY: 1 << 41)
  #expect(
    litBraillePixels(filled)
      == clippedRasterPixels((0..<8).flatMap { y in (0...2).map { ($0, y) } }))
}

@Test("BrailleCanvas primitives that overhang the buffer match the unclipped walks")
func brailleCanvasClippedPrimitivesMatchReference() {
  var random = ClippedRasterReference.Random(state: 0x5EED_F00D)
  for index in 0..<1_600 {
    // A few long lines; the rest overhang a 6 x 8 subpixel buffer by a little.
    let span = index < 100 ? -1_000...1_000 : -14...22
    let start = (x: random.next(span), y: random.next(span))
    let end = (x: random.next(span), y: random.next(span))
    var canvas = BrailleCanvas(width: 3, height: 2)
    canvas.line(from: start, to: end)
    var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    reference.line(from: start, to: end)
    #expect(litBraillePixels(canvas) == reference.pixels, "line \(start) \(end)")
  }
  for _ in 0..<400 {
    let x = random.next(-14...20)
    let y = random.next(-14...22)
    let width = random.next(-2...24)
    let height = random.next(-2...24)
    var canvas = BrailleCanvas(width: 3, height: 2)
    var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.strokeRect(x: x, y: y, width: width, height: height)
    reference.strokeRect(x: x, y: y, width: width, height: height)
    #expect(litBraillePixels(canvas) == reference.pixels, "strokeRect \(x) \(y) \(width) \(height)")
    canvas = BrailleCanvas(width: 3, height: 2)
    reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.fillRect(x: x, y: y, width: width, height: height)
    reference.fillRect(x: x, y: y, width: width, height: height)
    #expect(litBraillePixels(canvas) == reference.pixels, "fillRect \(x) \(y) \(width) \(height)")
  }
  for _ in 0..<400 {
    let cx = random.next(-14...20)
    let cy = random.next(-14...22)
    let rx = random.next(-1...16)
    let ry = random.next(-1...16)
    var canvas = BrailleCanvas(width: 3, height: 2)
    var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.strokeCircle(centerX: cx, centerY: cy, radius: rx)
    reference.strokeCircle(centerX: cx, centerY: cy, radius: rx)
    #expect(litBraillePixels(canvas) == reference.pixels, "strokeCircle \(cx) \(cy) \(rx)")
    canvas = BrailleCanvas(width: 3, height: 2)
    reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.fillCircle(centerX: cx, centerY: cy, radius: rx)
    reference.fillCircle(centerX: cx, centerY: cy, radius: rx)
    #expect(litBraillePixels(canvas) == reference.pixels, "fillCircle \(cx) \(cy) \(rx)")
    canvas = BrailleCanvas(width: 3, height: 2)
    reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
    reference.fillEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
    #expect(
      litBraillePixels(canvas) == reference.pixels, "fillEllipse \(cx) \(cy) \(rx) \(ry)")
    canvas = BrailleCanvas(width: 3, height: 2)
    reference = ClippedRasterReference.Buffer(width: 6, height: 8)
    canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
    reference.brailleStrokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
    #expect(
      litBraillePixels(canvas) == reference.pixels, "strokeEllipse \(cx) \(cy) \(rx) \(ry)")
  }
}
