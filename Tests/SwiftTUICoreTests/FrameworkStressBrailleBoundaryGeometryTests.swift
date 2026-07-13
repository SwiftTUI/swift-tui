import Testing

@testable import SwiftTUICore

@Suite("SwiftTUI Braille boundary-geometry stress behavior", .serialized)
struct FrameworkStressBrailleBoundaryGeometryTests {
  @Test("stress Braille boundary geometry 001 negative dimensions normalize independently")
  func brailleBoundaryGeometry001NegativeDimensionsNormalizeIndependently() {
    let canvas = BrailleCanvas(width: -7, height: -11)

    #expect(canvas.width == 0)
    #expect(canvas.height == 0)
    #expect(canvas.cells.isEmpty)
  }

  @Test("stress Braille boundary geometry 002 zero width preserves positive height")
  func brailleBoundaryGeometry002ZeroWidthPreservesPositiveHeight() {
    let canvas = BrailleCanvas(width: 0, height: 3)

    #expect(canvas.width == 0)
    #expect(canvas.height == 3)
    #expect(canvas.cells.count == 3)
    #expect(canvas.cells.allSatisfy { $0.isEmpty })
  }

  @Test("stress Braille boundary geometry 003 zero height preserves positive width")
  func brailleBoundaryGeometry003ZeroHeightPreservesPositiveWidth() {
    let canvas = BrailleCanvas(width: 5, height: 0)

    #expect(canvas.width == 5)
    #expect(canvas.height == 0)
    #expect(canvas.cells.isEmpty)
  }

  @Test("stress Braille boundary geometry 004 clearing one dot preserves its cell peers")
  func brailleBoundaryGeometry004ClearingOneDotPreservesCellPeers() {
    var canvas = BrailleCanvas(width: 1, height: 1)
    canvas.setPixel(x: 0, y: 0)
    canvas.setPixel(x: 1, y: 0)
    canvas.setPixel(x: 0, y: 3)

    canvas.clearPixel(x: 1, y: 0)

    #expect(canvas.cell(x: 0, y: 0).mask == 0x41)
  }

  @Test("stress Braille boundary geometry 005 out-of-range clears preserve every dot")
  func brailleBoundaryGeometry005OutOfRangeClearsPreserveEveryDot() {
    var canvas = BrailleCanvas(width: 1, height: 1)
    canvas.fillRect(x: 0, y: 0, width: 2, height: 4)
    let before = canvas

    canvas.clearPixel(x: -1, y: 0)
    canvas.clearPixel(x: 2, y: 0)
    canvas.clearPixel(x: 0, y: -1)
    canvas.clearPixel(x: 0, y: 4)

    #expect(canvas == before)
  }

  @Test("stress Braille boundary geometry 006 copied canvases diverge after mutation")
  func brailleBoundaryGeometry006CopiedCanvasesDivergeAfterMutation() {
    var original = BrailleCanvas(width: 1, height: 1)
    original.setPixel(x: 0, y: 0)
    var copy = original

    copy.setPixel(x: 1, y: 3)

    #expect(original.cell(x: 0, y: 0).mask == 0x01)
    #expect(copy.cell(x: 0, y: 0).mask == 0x81)
  }

  @Test("stress Braille boundary geometry 007 reversed shallow lines rasterize identically")
  func brailleBoundaryGeometry007ReversedShallowLinesRasterizeIdentically() {
    var forward = BrailleCanvas(width: 4, height: 2)
    var reverse = BrailleCanvas(width: 4, height: 2)

    forward.line(from: (x: 0, y: 1), to: (x: 7, y: 4))
    reverse.line(from: (x: 7, y: 4), to: (x: 0, y: 1))

    #expect(forward == reverse)
  }

  @Test("stress Braille boundary geometry 008 reversed steep lines rasterize identically")
  func brailleBoundaryGeometry008ReversedSteepLinesRasterizeIdentically() {
    var forward = BrailleCanvas(width: 3, height: 3)
    var reverse = BrailleCanvas(width: 3, height: 3)

    forward.line(from: (x: 1, y: 0), to: (x: 4, y: 11))
    reverse.line(from: (x: 4, y: 11), to: (x: 1, y: 0))

    #expect(forward == reverse)
  }

  @Test("stress Braille boundary geometry 009 a clipped horizontal line fills its visible span")
  func brailleBoundaryGeometry009ClippedHorizontalLineFillsVisibleSpan() {
    var canvas = BrailleCanvas(width: 2, height: 1)

    canvas.line(from: (x: -5, y: 2), to: (x: 8, y: 2))

    #expect(canvas.cell(x: 0, y: 0).mask == 0x24)
    #expect(canvas.cell(x: 1, y: 0).mask == 0x24)
  }

  @Test("stress Braille boundary geometry 010 an entirely exterior line leaves no residue")
  func brailleBoundaryGeometry010EntirelyExteriorLineLeavesNoResidue() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.line(from: (x: -8, y: -4), to: (x: -2, y: -1))

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test("stress Braille boundary geometry 011 a zero-length line sets exactly its endpoint")
  func brailleBoundaryGeometry011ZeroLengthLineSetsExactlyEndpoint() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.line(from: (x: 3, y: 6), to: (x: 3, y: 6))

    #expect(brailleLitPixelCount(canvas) == 1)
    #expect(canvas.cell(x: 1, y: 1).mask == 0x20)
  }

  @Test("stress Braille boundary geometry 012 minimum-integer short lines remain clipped")
  func brailleBoundaryGeometry012MinimumIntegerShortLinesRemainClipped() {
    var canvas = BrailleCanvas(width: 1, height: 1)

    canvas.line(from: (x: Int.min, y: Int.min), to: (x: Int.min + 1, y: Int.min))

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test("stress Braille boundary geometry 013 maximum-integer short lines remain clipped")
  func brailleBoundaryGeometry013MaximumIntegerShortLinesRemainClipped() {
    var canvas = BrailleCanvas(width: 1, height: 1)

    canvas.line(from: (x: Int.max - 1, y: Int.max), to: (x: Int.max, y: Int.max))

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test("stress Braille boundary geometry 014 a one-subpixel-wide stroke is a vertical line")
  func brailleBoundaryGeometry014OneSubpixelWideStrokeIsVerticalLine() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.strokeRect(x: 1, y: 1, width: 1, height: 6)

    #expect(brailleLitPixelCount(canvas) == 6)
    #expect(canvas.cell(x: 0, y: 0).mask == 0xB0)
    #expect(canvas.cell(x: 0, y: 1).mask == 0x38)
  }

  @Test("stress Braille boundary geometry 015 a one-subpixel-tall stroke is a horizontal line")
  func brailleBoundaryGeometry015OneSubpixelTallStrokeIsHorizontalLine() {
    var canvas = BrailleCanvas(width: 3, height: 1)

    canvas.strokeRect(x: 0, y: 3, width: 6, height: 1)

    #expect(brailleLitPixelCount(canvas) == 6)
    #expect(canvas.cells[0].allSatisfy { $0.mask == 0xC0 })
  }

  @Test("stress Braille boundary geometry 016 negative-origin strokes clip each edge independently")
  func brailleBoundaryGeometry016NegativeOriginStrokesClipEachEdgeIndependently() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.strokeRect(x: -1, y: -1, width: 4, height: 6)

    #expect(brailleLitPixelCount(canvas) == 7)
    #expect(canvas.cell(x: 0, y: 1).mask == 0x09)
    #expect(canvas.cell(x: 1, y: 0).mask == 0x47)
    #expect(canvas.cell(x: 1, y: 1).mask == 0x01)
  }

  @Test("stress Braille boundary geometry 017 nonpositive stroke extents are inert")
  func brailleBoundaryGeometry017NonpositiveStrokeExtentsAreInert() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.strokeRect(x: 0, y: 0, width: 0, height: 4)
    canvas.strokeRect(x: 0, y: 0, width: 4, height: 0)
    canvas.strokeRect(x: 0, y: 0, width: -4, height: 4)
    canvas.strokeRect(x: 0, y: 0, width: 4, height: -4)

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test(
    "stress Braille boundary geometry 018 negative-origin fills equal their visible intersection")
  func brailleBoundaryGeometry018NegativeOriginFillsEqualVisibleIntersection() {
    var clipped = BrailleCanvas(width: 2, height: 2)
    var intersection = BrailleCanvas(width: 2, height: 2)

    clipped.fillRect(x: -2, y: -3, width: 5, height: 8)
    intersection.fillRect(x: 0, y: 0, width: 3, height: 5)

    #expect(clipped == intersection)
  }

  @Test("stress Braille boundary geometry 019 fully exterior fills leave no residue")
  func brailleBoundaryGeometry019FullyExteriorFillsLeaveNoResidue() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.fillRect(x: 7, y: 8, width: 5, height: 6)

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test("stress Braille boundary geometry 020 nonpositive fill extents are inert")
  func brailleBoundaryGeometry020NonpositiveFillExtentsAreInert() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.fillRect(x: 0, y: 0, width: 0, height: 4)
    canvas.fillRect(x: 0, y: 0, width: 4, height: 0)
    canvas.fillRect(x: 0, y: 0, width: -4, height: 4)
    canvas.fillRect(x: 0, y: 0, width: 4, height: -4)

    #expect(brailleLitPixelCount(canvas) == 0)
  }

  @Test("stress Braille boundary geometry 021 negative circle radii are inert")
  func brailleBoundaryGeometry021NegativeCircleRadiiAreInert() {
    var stroke = BrailleCanvas(width: 2, height: 2)
    var fill = BrailleCanvas(width: 2, height: 2)

    stroke.strokeCircle(centerX: 2, centerY: 4, radius: -1)
    fill.fillCircle(centerX: 2, centerY: 4, radius: -1)

    #expect(brailleLitPixelCount(stroke) == 0)
    #expect(brailleLitPixelCount(fill) == 0)
  }

  @Test("stress Braille boundary geometry 022 a zero-radius filled circle sets only its center")
  func brailleBoundaryGeometry022ZeroRadiusFilledCircleSetsOnlyCenter() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.fillCircle(centerX: 2, centerY: 4, radius: 0)

    #expect(brailleLitPixelCount(canvas) == 1)
    #expect(canvas.cell(x: 1, y: 1).mask == 0x01)
  }

  @Test("stress Braille boundary geometry 023 clipped circle fills match visible scanline bounds")
  func brailleBoundaryGeometry023ClippedCircleFillsMatchVisibleScanlineBounds() {
    var canvas = BrailleCanvas(width: 2, height: 2)

    canvas.fillCircle(centerX: 0, centerY: 0, radius: 2)

    #expect(brailleLitPixelCount(canvas) == 6)
    #expect(canvas.cell(x: 0, y: 0).mask == 0x1F)
    #expect(canvas.cell(x: 1, y: 0).mask == 0x01)
  }

  @Test("stress Braille boundary geometry 024 zero-width ellipses become vertical diameters")
  func brailleBoundaryGeometry024ZeroWidthEllipsesBecomeVerticalDiameters() {
    var filled = BrailleCanvas(width: 3, height: 3)
    var stroked = BrailleCanvas(width: 3, height: 3)

    filled.fillEllipse(centerX: 3, centerY: 5, radiusX: 0, radiusY: 4)
    stroked.strokeEllipse(centerX: 3, centerY: 5, radiusX: 0, radiusY: 4)

    #expect(filled == stroked)
    #expect(brailleLitPixelCount(filled) == 9)
  }

  @Test("stress Braille boundary geometry 025 zero-height ellipses become horizontal diameters")
  func brailleBoundaryGeometry025ZeroHeightEllipsesBecomeHorizontalDiameters() {
    var filled = BrailleCanvas(width: 4, height: 2)
    var stroked = BrailleCanvas(width: 4, height: 2)

    filled.fillEllipse(centerX: 4, centerY: 3, radiusX: 3, radiusY: 0)
    stroked.strokeEllipse(centerX: 4, centerY: 3, radiusX: 3, radiusY: 0)

    #expect(filled == stroked)
    #expect(brailleLitPixelCount(filled) == 7)
  }
}

private func brailleLitPixelCount(_ canvas: BrailleCanvas) -> Int {
  canvas.cells.reduce(into: 0) { total, row in
    total += row.reduce(into: 0) { $0 += $1.mask.nonzeroBitCount }
  }
}
