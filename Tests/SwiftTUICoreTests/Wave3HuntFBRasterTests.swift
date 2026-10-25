// Wave-3 regression hunt, part FB (STUI-1167): the raster neighbours of the
// FW3-G repairs (d751e650) — far canvas lines at the buffer edges and
// parametric ellipse outlines above the switch-over on other buffers. Cases
// w3fb031-033; the brief and hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-3-hunt/fb/. The
// pre-repair walks are `ClippedRasterReference` (BrailleCanvasTests.swift).
import Foundation
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

/// A Braille context of `width` x `height` cells.
private func w3fbBrailleContext(width: Int = 4, height: Int = 2) -> CanvasContext {
  CanvasContext(
    canvas: CanvasGridBuffer(size: CellSize(width: width, height: height), grid: .braille2x4),
    foreground: .white,
    background: nil
  )
}

private func w3fbLitGridSamples(_ buffer: CanvasGridBuffer) -> Set<ClippedRasterPixel> {
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

/// One outline whose repaired pixels differ from the reference walk's.
private struct W3FBMismatch: CustomStringConvertible {
  var label: String
  var onlyRepaired: Int
  var onlyReference: Int
  var description: String { "\(label): +\(onlyRepaired) -\(onlyReference)" }
}

@Suite(.serialized)
struct Wave3HuntFBRasterTests {
  // w3fb031: far horizontal and vertical lines whose endpoint difference
  // overflows light the canvas's last sample row and column exactly as the
  // near lines do.
  @Test("w3fb031: far lines on the canvas's last sample row and column match the near lines")
  func w3fb031FarLinesOnTheCanvasEdgesMatchTheNearLines() {
    func lit(_ start: Point, _ end: Point) -> Set<ClippedRasterPixel> {
      var context = w3fbBrailleContext()
      context.line(from: start, to: end)
      return w3fbLitGridSamples(context.canvas)
    }
    let lastRow = lit(Point(x: -1, y: 1.8), Point(x: 5, y: 1.8))
    #expect(lastRow == clippedRasterPixels((0..<8).map { ($0, 7) }))
    #expect(lit(Point(x: -1.5e308, y: 1.8), Point(x: 1.5e308, y: 1.8)) == lastRow)
    let lastColumn = lit(Point(x: 3.7, y: -1), Point(x: 3.7, y: 3))
    #expect(lastColumn == clippedRasterPixels((0..<8).map { (7, $0) }))
    #expect(lit(Point(x: 3.7, y: 1.5e308), Point(x: 3.7, y: -1.5e308)) == lastColumn)
    let firstRow = lit(Point(x: 5, y: 0.1), Point(x: -1, y: 0.1))
    #expect(lit(Point(x: 1.7e308, y: 0.1), Point(x: -1.7e308, y: 0.1)) == firstRow)
  }

  // w3fb032: above the switch-over on a wide and a one-cell buffer, the
  // outlines light the reference walks' in-buffer samples.
  @Test("w3fb032: ellipses above the switch-over match the walks on wide and one-cell buffers")
  func w3fb032EllipsesAboveSwitchOverMatchWalksOnOtherBuffers() throws {
    var random = ClippedRasterReference.Random(state: 0x3FB_0032)
    var braille: [W3FBMismatch] = []
    var grid: [W3FBMismatch] = []
    var crossing = 0
    var compared = 0
    for (cellWidth, cellHeight) in [(40, 6), (1, 1)] {
      let width = cellWidth * 2
      let height = cellHeight * 4
      let switchOver = 4_096 + 4 * (width + height)
      for _ in 0..<30 {
        let sum = random.next((switchOver + 1)...(switchOver + 2_500))
        let rx = random.next(1...(sum - 1))
        let ry = sum - rx
        let phi = Double(random.next(0...3_599)) / 3_600 * 2 * Double.pi
        let px = random.next(0...(width - 1))
        let py = random.next(0...(height - 1))
        let cx = px - Int((Double(rx) * cos(phi)).rounded())
        let cy = py - Int((Double(ry) * sin(phi)).rounded())
        try #require(
          !ClippedRaster.usesExactOutline(radiusX: rx, radiusY: ry, width: width, height: height))
        let label = "\(width)x\(height) cx \(cx) cy \(cy) rx \(rx) ry \(ry)"
        var canvas = BrailleCanvas(width: cellWidth, height: cellHeight)
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        var reference = ClippedRasterReference.Buffer(width: width, height: height)
        reference.brailleStrokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        if !reference.pixels.isEmpty { crossing += 1 }
        let repaired = litBraillePixels(canvas)
        if repaired != reference.pixels {
          braille.append(
            .init(
              label: label, onlyRepaired: repaired.subtracting(reference.pixels).count,
              onlyReference: reference.pixels.subtracting(repaired).count))
        }
        var buffer = CanvasGridBuffer(
          size: CellSize(width: cellWidth, height: cellHeight), grid: .braille2x4)
        buffer.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        var gridReference = ClippedRasterReference.Buffer(width: width, height: height)
        gridReference.gridStrokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        let gridRepaired = w3fbLitGridSamples(buffer)
        if gridRepaired != gridReference.pixels {
          grid.append(
            .init(
              label: label, onlyRepaired: gridRepaired.subtracting(gridReference.pixels).count,
              onlyReference: gridReference.pixels.subtracting(gridRepaired).count))
        }
        compared += 1
      }
    }
    try #require(compared == 60 && crossing >= 40, "\(crossing) of \(compared) cross")
    // Contract: ClippedRaster.swift:20-24; CanvasGrid.swift:120-125.
    #expect(braille.isEmpty, "\(braille.count) of \(compared): \(braille.prefix(4))")
    #expect(grid.isEmpty, "\(grid.count) of \(compared): \(grid.prefix(4))")
  }

  // w3fb033: outlines that pass around the buffer, and outlines whose poles sit
  // on the buffer's corners, light exactly the walks' in-buffer samples.
  @Test("w3fb033: enclosing and corner-pole outlines above the switch-over match the walks")
  func w3fb033EllipseEnclosingTheBufferLightsNothing() {
    let width = 8
    let height = 8
    var cases: [(label: String, cx: Int, cy: Int, rx: Int, ry: Int)] = [
      ("enclosing round", 4, 4, 5_000, 5_000),
      ("enclosing flat", 4, 4, 9_000, 3_000),
    ]
    for (rx, ry) in [(5_000, 5_000), (6_000, 2)] {
      cases += [
        ("right pole on (0,0) rx \(rx)", -rx, 0, rx, ry),
        ("left pole on (7,7) rx \(rx)", width - 1 + rx, height - 1, rx, ry),
        ("bottom pole on (0,0) rx \(rx)", 0, -ry, rx, ry),
        ("top pole on (7,7) rx \(rx)", width - 1, height - 1 + ry, rx, ry),
      ]
    }
    var mismatches: [String] = []
    for entry in cases {
      var canvas = BrailleCanvas(width: width / 2, height: height / 4)
      canvas.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      var reference = ClippedRasterReference.Buffer(width: width, height: height)
      reference.brailleStrokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      if litBraillePixels(canvas) != reference.pixels {
        mismatches.append("braille \(entry.label)")
      }
      var buffer = CanvasGridBuffer(
        size: CellSize(width: width / 2, height: height / 4), grid: .braille2x4)
      buffer.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      var gridReference = ClippedRasterReference.Buffer(width: width, height: height)
      gridReference.gridStrokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      if w3fbLitGridSamples(buffer) != gridReference.pixels {
        mismatches.append("grid \(entry.label)")
      }
    }
    #expect(mismatches.isEmpty, "\(mismatches)")
  }
}
