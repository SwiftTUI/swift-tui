// Wave-2 regression hunt, part FB (STUI-1165): the clipped integer raster,
// Canvas segment clipping and gradient assignment at the neighbours of the
// FW-C (6d877a7d) and FW-E (ef4ce264) repairs. Cases w2fb010, 011, 013, 017,
// 018, 019, 026 and 028; the brief and hypotheses live in the org root's
// docs/reports/evidence/2026-10-25-campaign-two-wave-2-hunt/fb/. The
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

/// Keeps an unmarked reproduction path (`SWIFTTUI_W2HUNT_UNMARKED=1`) while
/// limiting each guard to its exact reproduced assertion.
private func w2fbKnown(_ comment: Comment, _ body: () throws -> Void) rethrows {
  if ProcessInfo.processInfo.environment["SWIFTTUI_W2HUNT_UNMARKED"] == "1" {
    try body()
  } else {
    withKnownIssue(comment) { try body() }
  }
}

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
    w2fbKnown(
      "NEW-1: w2fb011: CanvasContext.line((-1e308, 0.5), (1e308, 0.5)) lights no sample; SegmentClipping.clipped rejects a segment whose finite endpoints have a non-finite difference (SaturatingConversion.swift:67-68), so the visible part is skipped; contract: CanvasDrawing.swift:188-191 (only a non-finite endpoint draws nothing; the part inside the canvas is rasterized); adjacent STUI-753"
    ) {
      #expect(lit == expected, "lit \(lit.count) samples")
    }
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
    w2fbKnown(
      "NEW-2: w2fb017: just above the 4,096 + 4(w+h) switch-over, BrailleCanvas.strokeEllipse lights a different in-buffer pixel set from the parametric walk it replaces for 13 of 24 flat ellipses (the dot at the row change moves or disappears); ClippedRaster.ellipseOutline rounds each column's and row's crossing (ClippedRaster.swift:322-374) where the walk rounds its samples and joins them with lines; contract: ClippedRaster.swift:8-9, CanvasGrid.swift:120-122 (in-buffer output equals the unclipped walk); adjacent STUI-753"
    ) {
      #expect(mismatches.isEmpty, "\(mismatches.count) of \(compared): \(mismatches.prefix(4))")
    }
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
    w2fbKnown(
      "NEW-2: w2fb018: just above the switch-over, strokeEllipse(r, r) with r = 2081 lights a different in-buffer pixel set from the parametric walk at 44 of 48 crossing angles (at 45 degrees the walk lights (4, 4) and the outline lights only (4, 5) and (5, 4)); ClippedRaster.ellipseOutline rounds each column's and row's crossing (ClippedRaster.swift:322-374) where the walk rounds its samples and joins them with lines; contract: ClippedRaster.swift:8-9; adjacent STUI-753"
    ) {
      #expect(
        above.ellipses.isEmpty, "\(above.ellipses.count) of 48: \(above.ellipses.prefix(4))")
    }
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
    w2fbKnown(
      "NEW-2: w2fb028: CanvasGridBuffer.strokeEllipse just above the switch-over lights a different in-buffer pixel set from its parametric walk for 9 of 16 flat and round placements; ClippedRaster.ellipseOutline (ClippedRaster.swift:322-374); contract: CanvasGrid.swift:120-122; adjacent STUI-753"
    ) {
      #expect(mismatches.isEmpty, "\(mismatches.count) of \(cases.count): \(mismatches.prefix(4))")
    }
  }
}
