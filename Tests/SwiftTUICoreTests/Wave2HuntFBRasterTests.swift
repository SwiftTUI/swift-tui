// Wave-2 regression hunt, part FB (STUI-1165): the clipped integer raster,
// Canvas segment clipping and gradient assignment at the neighbours of the
// FW-C (6d877a7d) and FW-E (ef4ce264) repairs. Cases w2fb010, 011, 013, 017,
// 018, 019, 026 and 028; the brief and hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-2-hunt/fb/. The
// pre-repair walks are `ClippedRasterReference` (BrailleCanvasTests.swift).
// Wave 3 FW3-G (STUI-1245, STUI-1246) promoted this file's guards and added
// neighbours wave3g06-08, 10 and 11; its evidence is in the org root's
// docs/reports/evidence/2026-10-24-campaign-two-wave-3/fw3-g/.
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

/// A 4 x 2 cell Braille context: 8 x 8 grid samples.
private func w2fbBrailleContext() -> CanvasContext {
  CanvasContext(
    canvas: CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4),
    foreground: .white,
    background: nil
  )
}

private func w2fbLitGridSamples(_ buffer: CanvasGridBuffer) -> Set<ClippedRasterPixel> {
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

/// A pixel-set difference, formatted for an expectation message.
private struct W2FBMismatch: CustomStringConvertible {
  var label: String
  var onlyRepaired: Set<ClippedRasterPixel>
  var onlyReference: Set<ClippedRasterPixel>

  var description: String {
    let repaired = onlyRepaired.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    let reference = onlyReference.sorted { ($0.y, $0.x) < ($1.y, $1.x) }
    return "\(label): only repaired \(repaired), only reference \(reference)"
  }
}

private func w2fbCompare(
  _ label: String,
  repaired: Set<ClippedRasterPixel>,
  reference: Set<ClippedRasterPixel>,
  into mismatches: inout [W2FBMismatch]
) {
  guard repaired != reference else { return }
  mismatches.append(
    W2FBMismatch(
      label: label,
      onlyRepaired: repaired.subtracting(reference),
      onlyReference: reference.subtracting(repaired)))
}

/// `SegmentClipping.clipped` as written in ef4ce264, before FW3-G (STUI-1245),
/// for the bit-for-bit comparison of segments whose differences are finite.
private enum W3GPreFixSegmentClipping {
  static func clipped(
    from start: Point,
    to end: Point,
    within limit: Double
  ) -> (start: Point, end: Point)? {
    guard start.x.isFinite, start.y.isFinite, end.x.isFinite, end.y.isFinite,
      (end.x - start.x).isFinite, (end.y - start.y).isFinite
    else {
      return nil
    }
    func outcode(_ point: Point) -> Int {
      (point.x < -limit ? 1 : 0) | (point.x > limit ? 2 : 0)
        | (point.y < -limit ? 4 : 0) | (point.y > limit ? 8 : 0)
    }
    func crossing(x: Double, _ a: Point, _ b: Point) -> Point {
      let (near, far) = abs(a.x - x) <= abs(b.x - x) ? (a, b) : (b, a)
      return Point(x: x, y: near.y + (far.y - near.y) * ((x - near.x) / (far.x - near.x)))
    }
    func crossing(y: Double, _ a: Point, _ b: Point) -> Point {
      let (near, far) = abs(a.y - y) <= abs(b.y - y) ? (a, b) : (b, a)
      return Point(x: near.x + (far.x - near.x) * ((y - near.y) / (far.y - near.y)), y: y)
    }
    var a = start
    var b = end
    var codeA = outcode(a)
    var codeB = outcode(b)
    for _ in 0..<8 {
      if codeA | codeB == 0 {
        return (a, b)
      }
      if codeA & codeB != 0 {
        return nil
      }
      let outside = codeA != 0 ? codeA : codeB
      let point: Point
      if outside & 8 != 0 {
        point = crossing(y: limit, a, b)
      } else if outside & 4 != 0 {
        point = crossing(y: -limit, a, b)
      } else if outside & 2 != 0 {
        point = crossing(x: limit, a, b)
      } else {
        point = crossing(x: -limit, a, b)
      }
      if outside == codeA {
        a = point
        codeA = outcode(a)
      } else {
        b = point
        codeB = outcode(b)
      }
    }
    func clamped(_ point: Point) -> Point {
      Point(x: min(max(point.x, -limit), limit), y: min(max(point.y, -limit), limit))
    }
    return (clamped(a), clamped(b))
  }
}

/// The in-buffer pixels `ClippedRaster.ellipseOutline` lights, the crossing
/// outline kept beyond the walk's budget and domain.
private func w3gCrossingOutline(
  centerX: Int, centerY: Int, radiusX: Int, radiusY: Int, width: Int, height: Int
) -> Set<ClippedRasterPixel> {
  var pixels: Set<ClippedRasterPixel> = []
  ClippedRaster.ellipseOutline(
    centerX: centerX, centerY: centerY, radiusX: radiusX, radiusY: radiusY, width: width,
    height: height
  ) { pixels.insert(ClippedRasterPixel(x: $0, y: $1)) }
  return pixels
}

@Suite("Wave-2 hunt FB: clipped raster and canvas neighbours")
struct Wave2HuntFBRasterTests {
  // MARK: - FW-C (STUI-1127)

  @Test("w2fb010: RadialGradient and AngularGradient crossing assignments keep every stop")
  func w2fb010RadialAndAngularGradientCrossingAssignment() {
    let gradient = Gradient(stops: [
      .init(color: .red, location: 0), .init(color: .green, location: 0.5),
      .init(color: .blue, location: 1),
    ])
    let expected: [Gradient.Stop] = [
      .init(color: .green, location: 0.5), .init(color: .red, location: 0.6),
      .init(color: .blue, location: 1),
    ]
    func close(_ actual: [Gradient.Stop]) -> Bool {
      actual.count == expected.count
        && zip(actual, expected).allSatisfy { lhs, rhs in
          lhs.location == rhs.location
            && (lhs.color.animatableData - rhs.color.animatableData).magnitudeSquared < 1e-12
        }
    }
    var radial = RadialGradient(gradient: gradient, center: .center, startRadius: 0, endRadius: 8)
    var radialData = radial.animatableData
    radialData.first.elements[0].second = 0.6
    radial.animatableData = radialData
    #expect(close(radial.gradient.stops), "\(radial.gradient.stops)")

    var angular = AngularGradient(
      gradient: gradient, center: .center, startAngle: .zero, endAngle: .degrees(360))
    var angularData = angular.animatableData
    angularData.first.elements[0].second = 0.6
    angular.animatableData = angularData
    #expect(close(angular.gradient.stops), "\(angular.gradient.stops)")
  }

  // MARK: - FW-E segment clipping (STUI-753)

  @Test(
    "w2fb011: a canvas line whose finite endpoints span the Double range draws its visible part")
  func w2fb011CanvasLineSpanningTheDoubleRangeDrawsVisiblePart() throws {
    var near = w2fbBrailleContext()
    near.line(from: Point(x: -1, y: 0.5), to: Point(x: 5, y: 0.5))
    let expected = w2fbLitGridSamples(near.canvas)
    try #require(expected == clippedRasterPixels((0..<8).map { ($0, 2) }), "\(expected)")

    // Control: the difference of these endpoints is finite.
    var control = w2fbBrailleContext()
    control.line(from: Point(x: -1e308, y: 0.5), to: Point(x: 1e300, y: 0.5))
    #expect(w2fbLitGridSamples(control.canvas) == expected)

    // Both endpoints are finite; only `end - start` leaves the Double range.
    var far = w2fbBrailleContext()
    far.line(from: Point(x: -1e308, y: 0.5), to: Point(x: 1e308, y: 0.5))
    let lit = w2fbLitGridSamples(far.canvas)
    // STUI-1245 (repaired): the segment is clipped in a halved coordinate
    // space. Contract: CanvasDrawing.swift:188-191.
    #expect(lit == expected, "lit \(lit.count) samples")
  }

  @Test("w2fb013: canvas lines at and beyond the Int.max / 16 clip limit match the in-range line")
  func w2fb013CanvasLineAtTheClipLimitMatchesInRangeLine() {
    var near = w2fbBrailleContext()
    near.line(from: Point(x: 0.25, y: 0.5), to: Point(x: 10, y: 0.5))
    let expected = w2fbLitGridSamples(near.canvas)
    #expect(expected == clippedRasterPixels((0..<8).map { ($0, 2) }))
    for end in [Double(Int.max / 16), 1e18] {
      var line = w2fbBrailleContext()
      line.line(from: Point(x: 0.25, y: 0.5), to: Point(x: end, y: 0.5))
      #expect(w2fbLitGridSamples(line.canvas) == expected, "end \(end)")
    }
    var nearDiagonal = w2fbBrailleContext()
    nearDiagonal.line(from: .zero, to: Point(x: 4, y: 4))
    var farDiagonal = w2fbBrailleContext()
    farDiagonal.line(from: .zero, to: Point(x: 1e18, y: 1e18))
    #expect(w2fbLitGridSamples(farDiagonal.canvas) == w2fbLitGridSamples(nearDiagonal.canvas))
  }

  @Test(
    "w2fb026: canvas rectangles whose corners sit at the Double extremes draw their visible part")
  func w2fb026CanvasRectanglesAtTheDoubleExtremes() {
    let rect = Rect(origin: Point(x: -1e308, y: 0.25), size: Size(width: 1.7e308, height: 1))
    var filled = w2fbBrailleContext()
    filled.fillRect(rect)
    var fillExpected: [(Int, Int)] = []
    for y in 1...4 { fillExpected += (0..<8).map { ($0, y) } }
    #expect(w2fbLitGridSamples(filled.canvas) == clippedRasterPixels(fillExpected))
    var stroked = w2fbBrailleContext()
    stroked.strokeRect(rect)
    #expect(
      w2fbLitGridSamples(stroked.canvas)
        == clippedRasterPixels((0..<8).map { ($0, 1) } + (0..<8).map { ($0, 4) }))
  }

  // MARK: - FW-E clipped integer primitives (STUI-753)

  @Test("w2fb019: every clipped line in a small window lights the Bresenham walk's pixels")
  func w2fb019ClippedLinesMatchBresenhamExhaustively() {
    var points: [(x: Int, y: Int)] = []
    for y in -3...10 {
      for x in -3...8 { points.append((x, y)) }
    }
    func inside(_ point: (x: Int, y: Int)) -> Bool {
      point.x >= 0 && point.x < 6 && point.y >= 0 && point.y < 8
    }
    var compared = 0
    var mismatches: [W2FBMismatch] = []
    for start in points {
      for end in points where !(inside(start) && inside(end)) {
        var canvas = BrailleCanvas(width: 3, height: 2)
        canvas.line(from: start, to: end)
        var reference = ClippedRasterReference.Buffer(width: 6, height: 8)
        reference.line(from: start, to: end)
        w2fbCompare(
          "line \(start) \(end)", repaired: litBraillePixels(canvas), reference: reference.pixels,
          into: &mismatches)
        compared += 1
      }
    }
    #expect(compared == 168 * 168 - 48 * 48)
    #expect(mismatches.isEmpty, "\(mismatches.prefix(5))")
  }

  @Test("w2fb017: flat ellipse outlines just above the switch-over match the parametric walk")
  func w2fb017FlatEllipseOutlineAtSwitchOverMatchesParametricWalk() throws {
    // An 8 x 8 buffer switches to `ellipseOutline` above 4,096 + 4 * 16 = 4,160.
    try #require(!ClippedRaster.usesExactOutline(radiusX: 4_160, radiusY: 1, width: 8, height: 8))
    try #require(ClippedRaster.usesExactOutline(radiusX: 4_159, radiusY: 1, width: 8, height: 8))
    var mismatches: [W2FBMismatch] = []
    var compared = 0
    for ry in [1, 3, 5] {
      for k in 0..<8 {
        let rx = 4_161 - ry + k
        // The parametric walk changes rows where sin(theta) = 0.5; put that
        // column in the middle of the buffer.
        let cx = 4 - Int((Double(rx) * 3.0.squareRoot() / 2).rounded())
        let cy = 4
        var canvas = BrailleCanvas(width: 4, height: 2)
        canvas.strokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        var reference = ClippedRasterReference.Buffer(width: 8, height: 8)
        reference.brailleStrokeEllipse(centerX: cx, centerY: cy, radiusX: rx, radiusY: ry)
        try #require(!reference.pixels.isEmpty, "rx \(rx) ry \(ry) misses the buffer")
        w2fbCompare(
          "rx \(rx) ry \(ry) cx \(cx)", repaired: litBraillePixels(canvas),
          reference: reference.pixels, into: &mismatches)
        compared += 1
      }
    }
    #expect(compared == 24)
    // STUI-1246 (repaired): the outline walks the walk's own samples near the
    // buffer. Contract: ClippedRaster.swift:8-9, CanvasGrid.swift:120-122.
    #expect(mismatches.isEmpty, "\(mismatches.count) of \(compared): \(mismatches.prefix(4))")
  }

  @Test(
    "w2fb018: round outlines just above the switch-over match the parametric and midpoint walks")
  func w2fb018RoundOutlinesAtSwitchOverMatchReferenceWalks() throws {
    func placements(radius: Int) -> [(cx: Int, cy: Int)] {
      (0..<48).map { k in
        let phi = Double(k) * 7.5 * Double.pi / 180
        return (
          4 - Int((Double(radius) * cos(phi)).rounded()),
          4 - Int((Double(radius) * sin(phi)).rounded())
        )
      }
    }
    func mismatches(radius: Int) throws -> (ellipses: [W2FBMismatch], circles: [W2FBMismatch]) {
      var ellipses: [W2FBMismatch] = []
      var circles: [W2FBMismatch] = []
      for (index, centre) in placements(radius: radius).enumerated() {
        var ellipse = BrailleCanvas(width: 4, height: 2)
        ellipse.strokeEllipse(
          centerX: centre.cx, centerY: centre.cy, radiusX: radius, radiusY: radius)
        var ellipseReference = ClippedRasterReference.Buffer(width: 8, height: 8)
        ellipseReference.brailleStrokeEllipse(
          centerX: centre.cx, centerY: centre.cy, radiusX: radius, radiusY: radius)
        try #require(!ellipseReference.pixels.isEmpty, "placement \(index) misses the buffer")
        w2fbCompare(
          "ellipse r \(radius) at \(Double(index) * 7.5) deg", repaired: litBraillePixels(ellipse),
          reference: ellipseReference.pixels, into: &ellipses)
        var circle = BrailleCanvas(width: 4, height: 2)
        circle.strokeCircle(centerX: centre.cx, centerY: centre.cy, radius: radius)
        var circleReference = ClippedRasterReference.Buffer(width: 8, height: 8)
        circleReference.strokeCircle(centerX: centre.cx, centerY: centre.cy, radius: radius)
        w2fbCompare(
          "circle r \(radius) at \(Double(index) * 7.5) deg", repaired: litBraillePixels(circle),
          reference: circleReference.pixels, into: &circles)
      }
      return (ellipses, circles)
    }
    // Control: radii summing to exactly the switch-over keep the original walks.
    let control = try mismatches(radius: 2_080)
    #expect(control.ellipses.isEmpty, "\(control.ellipses.prefix(4))")
    #expect(control.circles.isEmpty, "\(control.circles.prefix(4))")
    let above = try mismatches(radius: 2_081)
    // The midpoint circle and the crossing outline agree at every placement.
    #expect(above.circles.isEmpty, "\(above.circles.count) of 48: \(above.circles.prefix(4))")
    // STUI-1246 (repaired). Contract: ClippedRaster.swift:8-9.
    #expect(
      above.ellipses.isEmpty, "\(above.ellipses.count) of 48: \(above.ellipses.prefix(4))")
  }

  @Test(
    "w2fb028: grid-buffer ellipse outlines just above the switch-over match the parametric walk")
  func w2fb028GridEllipseOutlineAtSwitchOverMatchesParametricWalk() throws {
    func fresh() -> CanvasGridBuffer {
      CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4)
    }
    try #require(fresh().pixelWidth == 8 && fresh().pixelHeight == 8)
    var cases: [(label: String, cx: Int, cy: Int, rx: Int, ry: Int)] = []
    for k in 0..<8 {
      let rx = 4_160 + k
      cases.append(
        ("flat rx \(rx)", 4 - Int((Double(rx) * 3.0.squareRoot() / 2).rounded()), 4, rx, 1))
    }
    for k in 0..<8 {
      let phi = Double(k) * 45 * Double.pi / 180
      cases.append(
        (
          "round at \(k * 45) deg", 4 - Int((2_081 * cos(phi)).rounded()),
          4 - Int((2_081 * sin(phi)).rounded()), 2_081, 2_081
        ))
    }
    var mismatches: [W2FBMismatch] = []
    for entry in cases {
      var buffer = fresh()
      buffer.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      var reference = ClippedRasterReference.Buffer(width: 8, height: 8)
      reference.gridStrokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      try #require(!reference.pixels.isEmpty, "\(entry.label) misses the buffer")
      w2fbCompare(
        entry.label, repaired: w2fbLitGridSamples(buffer), reference: reference.pixels,
        into: &mismatches)
    }
    // STUI-1246 (repaired). Contract: CanvasGrid.swift:120-122.
    #expect(mismatches.isEmpty, "\(mismatches.count) of \(cases.count): \(mismatches.prefix(4))")
  }

  // MARK: - Wave 3 FW3-G neighbours (STUI-1245, STUI-1246)

  @Test(
    "wave3g06: canvas lines whose finite endpoints span the Double range draw their visible part")
  func wave3g06CanvasLinesSpanningTheDoubleRangeDrawTheirVisiblePart() {
    func lit(_ start: Point, _ end: Point) -> Set<ClippedRasterPixel> {
      var context = w2fbBrailleContext()
      context.line(from: start, to: end)
      return w2fbLitGridSamples(context.canvas)
    }
    let column = lit(Point(x: 0.5, y: -1), Point(x: 0.5, y: 3))
    #expect(column == clippedRasterPixels((0..<8).map { (1, $0) }))
    #expect(lit(Point(x: 0.5, y: -1e308), Point(x: 0.5, y: 1e308)) == column)
    let row = lit(Point(x: -1, y: 0.5), Point(x: 5, y: 0.5))
    #expect(lit(Point(x: 1e308, y: 0.5), Point(x: -1e308, y: 0.5)) == row)
    let max = Double.greatestFiniteMagnitude
    #expect(
      lit(Point(x: -max, y: 1.25), Point(x: max, y: 1.25))
        == clippedRasterPixels((0..<8).map { ($0, 5) }))
    // Controls: rows off the canvas draw nothing, beyond and inside the limit.
    #expect(lit(Point(x: -1e308, y: 1e18), Point(x: 1e308, y: 1e18)).isEmpty)
    #expect(lit(Point(x: -1e308, y: 50), Point(x: 1e308, y: 50)).isEmpty)
  }

  @Test("wave3g07: segment clipping halves differences that leave the Double range")
  func wave3g07SegmentClippingHalvesOverflowingDifferences() {
    let limit = Double(Int.max / 16)
    func clip(_ start: Point, _ end: Point) -> [Point]? {
      SegmentClipping.clipped(from: start, to: end, within: limit).map { [$0.start, $0.end] }
    }
    #expect(
      clip(Point(x: -1e308, y: 0.5), Point(x: 1e308, y: 0.5))
        == [Point(x: -limit, y: 0.5), Point(x: limit, y: 0.5)])
    #expect(
      clip(Point(x: 1e308, y: 0.5), Point(x: -1e308, y: 0.5))
        == [Point(x: limit, y: 0.5), Point(x: -limit, y: 0.5)])
    #expect(
      clip(Point(x: 3, y: -1e308), Point(x: 3, y: 1e308))
        == [Point(x: 3, y: -limit), Point(x: 3, y: limit)])
    let max = Double.greatestFiniteMagnitude
    #expect(
      clip(Point(x: -max, y: 3), Point(x: max, y: 3))
        == [Point(x: -limit, y: 3), Point(x: limit, y: 3)])
    // Outside the square on one side, and a non-finite endpoint: nothing.
    #expect(clip(Point(x: -1e308, y: 2 * limit), Point(x: 1e308, y: 2 * limit)) == nil)
    #expect(clip(Point(x: -.infinity, y: 0.5), Point(x: 1e308, y: 0.5)) == nil)
    #expect(clip(Point(x: -1e308, y: .nan), Point(x: 1e308, y: 0.5)) == nil)
  }

  @Test("wave3g08: segments whose differences are finite clip exactly as before")
  func wave3g08SegmentClippingIsUnchangedForFiniteDifferences() {
    var random = ClippedRasterReference.Random(state: 0x3_6E0D_F00D)
    let scales = [1.0, 30, 1e6, 1e18, 1e150, 1e300]
    let limits = [Double(Int.max / 16), Double(Int.max / 8), 10]
    var differing: [String] = []
    for index in 0..<4_000 {
      func coordinate() -> Double {
        let scale = scales[random.next(0...(scales.count - 1))]
        return Double(random.next(-1_000_000...1_000_000)) / 1_000_000 * scale
      }
      let start = Point(x: coordinate(), y: coordinate())
      let end = Point(x: coordinate(), y: coordinate())
      let limit = limits[index % limits.count]
      let repaired = SegmentClipping.clipped(from: start, to: end, within: limit)
      let reference = W3GPreFixSegmentClipping.clipped(from: start, to: end, within: limit)
      let same =
        repaired.map { [$0.start, $0.end] } == reference.map { [$0.start, $0.end] }
      if !same { differing.append("\(start) \(end) \(limit)") }
    }
    #expect(differing.isEmpty, "\(differing.count): \(differing.prefix(4))")
  }

  @Test("wave3g10: ellipses above the switch-over light the walks' in-buffer pixels")
  func wave3g10EllipsesAboveTheSwitchOverMatchTheWalks() throws {
    var random = ClippedRasterReference.Random(state: 0xE11_1953)
    var cases: [(cx: Int, cy: Int, rx: Int, ry: Int)] = []
    func place(rx: Int, ry: Int, phi: Double) -> (cx: Int, cy: Int, rx: Int, ry: Int) {
      let px = random.next(0...7)
      let py = random.next(0...7)
      return (
        px - Int((Double(rx) * cos(phi)).rounded()), py - Int((Double(ry) * sin(phi)).rounded()),
        rx, ry
      )
    }
    for _ in 0..<90 {
      let sum = random.next(4_161...9_000)
      let rx = random.next(1...(sum - 1))
      let phi = Double(random.next(0...3_599)) / 3_600 * 2 * Double.pi
      cases.append(place(rx: rx, ry: sum - rx, phi: phi))
    }
    // Larger round outlines, and the sharp ends of a flat one.
    for k in 0..<4 { cases.append(place(rx: 60_000, ry: 59_993, phi: Double(k) * 1.1 + 0.2)) }
    for phi in [0.0, Double.pi, 0.004] { cases.append(place(rx: 100_000, ry: 7, phi: phi)) }

    var braille: [W2FBMismatch] = []
    var grid: [W2FBMismatch] = []
    var crossing = 0
    for entry in cases {
      let label = "cx \(entry.cx) cy \(entry.cy) rx \(entry.rx) ry \(entry.ry)"
      #expect(
        !ClippedRaster.usesExactOutline(radiusX: entry.rx, radiusY: entry.ry, width: 8, height: 8))
      var canvas = BrailleCanvas(width: 4, height: 2)
      canvas.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      var reference = ClippedRasterReference.Buffer(width: 8, height: 8)
      reference.brailleStrokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      if !reference.pixels.isEmpty { crossing += 1 }
      w2fbCompare(
        label, repaired: litBraillePixels(canvas), reference: reference.pixels, into: &braille)
      var buffer = CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4)
      buffer.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      var gridReference = ClippedRasterReference.Buffer(width: 8, height: 8)
      gridReference.gridStrokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      w2fbCompare(
        label, repaired: w2fbLitGridSamples(buffer), reference: gridReference.pixels, into: &grid)
    }
    try #require(crossing > cases.count * 3 / 4, "\(crossing) of \(cases.count) cross the buffer")
    #expect(braille.isEmpty, "\(braille.count) of \(cases.count): \(braille.prefix(3))")
    #expect(grid.isEmpty, "\(grid.count) of \(cases.count): \(grid.prefix(3))")
  }

  @Test("wave3g11: outlines beyond the walk's budget and domain keep the crossing outline")
  func wave3g11OutlinesBeyondTheWalkBudgetKeepTheCrossingOutline() {
    let flat = 1 << 40
    let round = 1 << 59
    let overflowing = Int.max / 8 + 1
    let cases: [(cx: Int, cy: Int, rx: Int, ry: Int)] = [
      // The sharp end of a flat ellipse: the walk takes about 2^40 samples per
      // pixel of arc there.
      (4 - flat, 4, flat, 1),
      // A radius whose angle margin alone exceeds the budget.
      (2 - round, 4, round, round),
      // 4 * (rx + ry) overflows Int: the unclipped walk would trap.
      (2 - overflowing, 4, overflowing, overflowing),
    ]
    for entry in cases {
      let expected = w3gCrossingOutline(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry, width: 8,
        height: 8)
      #expect(!expected.isEmpty, "rx \(entry.rx)")
      var canvas = BrailleCanvas(width: 4, height: 2)
      canvas.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      #expect(litBraillePixels(canvas) == expected, "braille rx \(entry.rx)")
      var buffer = CanvasGridBuffer(size: CellSize(width: 4, height: 2), grid: .braille2x4)
      buffer.strokeEllipse(
        centerX: entry.cx, centerY: entry.cy, radiusX: entry.rx, radiusY: entry.ry)
      #expect(w2fbLitGridSamples(buffer) == expected, "grid rx \(entry.rx)")
    }
  }
}
