import Testing

@testable import SwiftTUICore

@Suite
struct SampledStrokeTrackTests {
  private func litPixels(_ canvas: BrailleCanvas) -> [(x: Int, y: Int)] {
    var lit: [(x: Int, y: Int)] = []
    for y in 0..<canvas.subpixelHeight {
      for x in 0..<canvas.subpixelWidth
      where canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4) {
        lit.append((x, y))
      }
    }
    return lit
  }

  /// A circle of radius 18 subpixels, centered in a 20 x 10 cell canvas.
  private func strokedCircle() -> BrailleCanvas {
    var canvas = BrailleCanvas(width: 20, height: 10)
    canvas.strokeEllipse(centerX: 19, centerY: 19, radiusX: 18, radiusY: 18)
    return canvas
  }

  private var circleTrack: SampledStrokeTrack {
    .ellipse(centerX: 19, centerY: 19, radiusX: 18, radiusY: 18, aspectRatio: 2)
  }

  @Test("an ellipse starts at its trailing point and runs clockwise, as in SwiftUI")
  func ellipseStartAndDirection() throws {
    let track = circleTrack
    let first = try #require(track.points.first)
    #expect(first == Point(x: 37, y: 19))
    #expect(track.positions.first == 0)
    // Down first: the bottom is a quarter of the way round, the leading point
    // half, and the top three quarters.
    let length = track.length
    #expect(abs(track.position(nearestToX: 19, y: 37) - 0.25 * length) < 0.02 * length)
    #expect(abs(track.position(nearestToX: 1, y: 19) - 0.5 * length) < 0.02 * length)
    #expect(abs(track.position(nearestToX: 19, y: 1) - 0.75 * length) < 0.02 * length)
  }

  @Test("a circle's length is measured in cell widths")
  func lengthUnit() {
    // A subpixel is half a cell wide. At an aspect ratio of 2 it is also half a
    // cell width tall, so the circle is 2 pi r / 2 cell widths round.
    #expect(abs(circleTrack.length - .pi * 18) < 0.5)
    // A taller cell makes the same subpixels a longer way round.
    let tall = SampledStrokeTrack.ellipse(
      centerX: 19, centerY: 19, radiusX: 18, radiusY: 18, aspectRatio: 3)
    #expect(tall.length > circleTrack.length * 1.15)
  }

  @Test("a quarter trim keeps the lower trailing quadrant")
  func quarterTrim() {
    var canvas = strokedCircle()
    let whole = litPixels(canvas).count
    circleTrack.apply(StrokeMask(trim: StrokeTrim(from: 0, to: 0.25)), to: &canvas)
    let kept = litPixels(canvas)
    #expect(!kept.isEmpty)
    #expect(kept.allSatisfy { $0.x >= 18 && $0.y >= 18 })
    #expect(Double(kept.count) > 0.18 * Double(whole))
    #expect(Double(kept.count) < 0.32 * Double(whole))
  }

  @Test("an even dash keeps about half of the outline")
  func evenDash() throws {
    var canvas = strokedCircle()
    let whole = litPixels(canvas).count
    let dash = try #require(StrokeDashPattern(dash: [2, 2], phase: 0))
    circleTrack.apply(StrokeMask(dash: dash), to: &canvas)
    let kept = litPixels(canvas).count
    #expect(Double(kept) > 0.35 * Double(whole))
    #expect(Double(kept) < 0.65 * Double(whole))
  }

  @Test("a solid mask and a whole trim leave the stroke as it was rasterized")
  func untouchedWhenNothingIsMasked() {
    let original = strokedCircle()
    var solid = original
    circleTrack.apply(StrokeMask(), to: &solid)
    #expect(litPixels(solid).count == litPixels(original).count)
    var whole = original
    circleTrack.apply(StrokeMask(trim: StrokeTrim(from: 0, to: 1)), to: &whole)
    #expect(litPixels(whole).count == litPixels(original).count)
  }

  @Test("an empty trim clears the stroke")
  func emptyTrim() {
    var canvas = strokedCircle()
    circleTrack.apply(StrokeMask(trim: StrokeTrim(from: 0.5, to: 0.5)), to: &canvas)
    #expect(litPixels(canvas).isEmpty)
  }

  @Test("a capsule starts at the middle of its trailing edge and closes")
  func capsuleOutline() throws {
    let wide = SampledStrokeTrack.capsule(
      subpixelWidth: 40, subpixelHeight: 12, isHorizontal: true, radiusX: 5, radiusY: 5,
      aspectRatio: 2)
    let first = try #require(wide.points.first)
    let last = try #require(wide.points.last)
    #expect(first == Point(x: 39, y: 5))
    #expect(abs(last.x - first.x) < 1e-9 && abs(last.y - first.y) < 1e-9)
    // The bottom edge comes before the top edge.
    #expect(wide.position(nearestToX: 20, y: 10) < wide.position(nearestToX: 20, y: 0))
  }

  @Test("positions continue from one subpath to the next")
  func pathSubpaths() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 1, y: 0))
    path.move(to: Point(x: 0, y: 1))
    path.addLine(to: Point(x: 1, y: 1))
    let track = SampledStrokeTrack.path(
      path, subpixelWidth: 21, subpixelHeight: 9, aspectRatio: 2)
    // Two lines, each 20 subpixels, which is 10 cell widths.
    #expect(abs(track.length - 20) < 1e-9)
    #expect(track.position(nearestToX: 10, y: 0) < 10)
    #expect(track.position(nearestToX: 10, y: 8) > 10)
  }
}
