import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct AdversarialSetAPathStrokeBoundaryTests {
  @Test func setA576ReversingAnAlreadyEmptyTrimCannotResurrectItsStroke() {
    // Hypothesis: affine composition of two reversed trim intervals resurrects an empty outline.
    let empty = Rectangle().trim(from: 0.8, to: 0.2)
    let twice = empty.trim(from: 0.75, to: 0.25)
    #expect(empty.path(in: unit).elements.isEmpty)
    #expect(twice.path(in: unit).elements.isEmpty)
    #expect(ink(rows(empty.stroke(), width: 12, height: 6)) == 0)
    do {
      #expect(ink(rows(twice.stroke(), width: 12, height: 6)) == 0)
    }
  }

  @Test func setA577FiniteLineTrimsRemainScaleInvariantAcrossSquaredNormLimits() {
    // Hypothesis: squaring a finite length overflows or underflows before trim fractions are applied.
    for length in [1.0, 1e200, 1e-200] {
      let path = line(.zero, .init(x: length, y: 0))
      let points = path.trimmedPath(from: 0.25, to: 0.75).flattened().flatMap { $0 }
      if length == 1 {
        #expect(points.count == 2)
      } else {
        do {
          #expect(points.count == 2)
        }
      }
      if points.count == 2 {
        #expect(abs(points[0].x / length - 0.25) < 1e-12)
        #expect(abs(points[1].x / length - 0.75) < 1e-12)
      }
    }
  }

  @Test func setA578CollinearCurveBacktrackingMustSurviveFlattening() {
    // Hypothesis: perpendicular-to-line flatness discards a curve's collinear excursion beyond its endpoint.
    var path = Path()
    path.move(to: .zero)
    path.addQuadCurve(to: .init(x: 1, y: 0), control: .init(x: 3, y: 0))
    // x(t)=6t-5t² reaches 1.8 at t=0.6, then returns to 1.
    let points = path.flattened(tolerance: 0.001).flatMap { $0 }
    #expect(points.last == .init(x: 1, y: 0))
    do {
      #expect((points.map(\.x).max() ?? 0) > 1.79)
    }
  }

  @Test func setA579BoundaryToleranceMeasuresDistanceInsteadOfUnnormalizedCrossProduct() {
    // Hypothesis: a fixed cross-product epsilon classifies a clearly exterior point as a short edge's boundary.
    let tiny = Path([
      .move(to: .zero), .line(to: .init(x: 0.001, y: 0.001)),
      .line(to: .init(x: 0.001, y: 0)), .close,
    ])
    #expect(tiny.contains(.init(x: 0.0008, y: 0.0002)))
    // Distance to the diagonal exceeds 0.0003, far beyond the 0.000001 boundary tolerance.
    #expect(!tiny.scaledBy(sx: 1000, sy: 1000).contains(.init(x: 0, y: 0.5)))
    let exteriorIsContained = tiny.contains(.init(x: 0, y: 0.0005))
    do {
      #expect(!exteriorIsContained)
    }
  }

  @Test func setA580OppositeWindingHoleKeepsItsBoundaryButRejectsItsInterior() {
    // Hypothesis: signed crossings cancel the outer boundary itself or fail to cancel an oppositely wound hole.
    var path = Path(.init(origin: .zero, size: .init(width: 10, height: 10)))
    path.move(to: .init(x: 2, y: 2))
    path.addLine(to: .init(x: 2, y: 8))
    path.addLine(to: .init(x: 8, y: 8))
    path.addLine(to: .init(x: 8, y: 2))
    path.close()
    #expect(path.contains(.init(x: 1, y: 5)))
    #expect(path.contains(.init(x: 2, y: 5)))
    #expect(!path.contains(.init(x: 5, y: 5)))
    #expect(!path.contains(.init(x: 11, y: 5)))
  }

  @Test func setA581ClosedCubicLoopWithCoincidentEndpointsRetainsItsExcursion() {
    // Hypothesis: a zero endpoint chord is mistaken for a zero-length cubic even with distant control points.
    var path = Path()
    path.move(to: .zero)
    path.addCurve(to: .zero, control1: .init(x: 1, y: 0), control2: .init(x: 1, y: 1))
    let points = path.flattened(tolerance: 0.001).flatMap { $0 }
    #expect(points.count > 8)
    #expect(points.first == points.last)
    #expect((points.map(\.x).max() ?? 0) > 0.74)
    #expect(path.contains(.init(x: 0.4, y: 0.2)))
  }

  @Test func setA582FiniteOppositeHugeAnglesProduceOneClosedGeometricTurn() {
    // Hypothesis: overflowing endpoint subtraction rejects finite arc inputs instead of the documented full turn.
    var path = Path()
    path.addArc(
      center: .init(x: 3, y: 4), radius: 2,
      startAngle: .radians(-1e308), endAngle: .radians(1e308), clockwise: true)
    let points = path.flattened(tolerance: 0.001).flatMap { $0 }
    #expect(path.elements.count == 5)
    #expect(points.first == points.last)
    #expect(path.contains(.init(x: 3, y: 4)))
    #expect(!path.elements.contains(.close))
    #expect(points.allSatisfy { $0.x.isFinite && $0.y.isFinite })
  }

  @Test func setA583DegreeElevatedQuadraticAndCubicAgreeOnTheirFilledInterior() {
    // Hypothesis: different curve subdivision paths change fill classification for equivalent degree-elevated geometry.
    var quadratic = Path()
    quadratic.move(to: .zero)
    quadratic.addQuadCurve(to: .init(x: 6, y: 0), control: .init(x: 3, y: 6))
    quadratic.close()
    var cubic = Path()
    cubic.move(to: .zero)
    cubic.addCurve(to: .init(x: 6, y: 0), control1: .init(x: 2, y: 4), control2: .init(x: 4, y: 4))
    cubic.close()
    for point in [Point(x: 3, y: 2), .init(x: 3, y: 4), .init(x: 1, y: 0.5), .init(x: 1, y: 3)] {
      #expect(quadratic.contains(point) == cubic.contains(point))
    }
    #expect(quadratic.contains(.init(x: 3, y: 2)))
    #expect(!quadratic.contains(.init(x: 3, y: 4)))
  }

  @Test func setA584ArcConnectionUsesTheMostRecentMoveEvenWithoutASegment() {
    // Hypothesis: arc construction uses an earlier drawable endpoint instead of the latest move-only pen position.
    var path = line(.zero, .init(x: 8, y: 0))
    path.move(to: .init(x: 1, y: 0))
    let prefix = path.elements
    path.addArc(
      center: .zero, radius: 1, startAngle: .zero, endAngle: .degrees(90), clockwise: false)
    #expect(Array(path.elements.prefix(prefix.count)) == prefix)
    #expect(path.elements.count == prefix.count + 1)
    if case .curve? = path.elements.last {
    } else {
      Issue.record("Expected arc without an extra connector")
    }
  }

  @Test func setA585ExactTrimBoundaryBetweenContoursDoesNotKeepADeadPrecedingContour() {
    // Hypothesis: equality at the cumulative-length cut emits a zero segment or an implicit bridge across contours.
    var path = line(.zero, .init(x: 2, y: 0))
    path.move(to: .init(x: 100, y: 5))
    path.addLine(to: .init(x: 104, y: 5))
    #expect(
      path.trimmedPath(from: 1.0 / 3, to: 2.0 / 3).elements == [
        .move(to: .init(x: 100, y: 5)), .line(to: .init(x: 102, y: 5)),
      ])
  }

  @Test func setA586ZeroLengthDashRunsPreserveOnOffParity() throws {
    // Hypothesis: dropping zero-length runs flips parity or loops at an exact dash boundary.
    let pattern = try #require(StrokeDashPattern(dash: [0, 2, 1, 0], phase: 0))
    #expect(!pattern.isOn(at: 0))
    #expect(!pattern.isOn(at: 1.5))
    #expect(pattern.isOn(at: 2))
    #expect(pattern.isOn(at: 2.5))
    #expect(!pattern.isOn(at: 3))
  }

  @Test func setA587SubnormalDashPeriodsDoNotBecomeSolidByAnEpsilonFloor() throws {
    // Hypothesis: extremely small but representable dash periods are discarded as zero or cannot wrap.
    let unit = Double.leastNormalMagnitude / 16
    let pattern = try #require(StrokeDashPattern(dash: [unit, unit], phase: 0))
    #expect(pattern.isOn(at: unit / 2))
    #expect(!pattern.isOn(at: unit * 1.5))
    #expect(pattern.isOn(at: unit * 2.5))
  }

  @Test func setA588FinitePhaseAndPositionAreReducedBeforeTheirSumOverflows() throws {
    // Hypothesis: adding two finite dash coordinates before modular reduction produces NaN and a solid fallback.
    let huge = 1e308
    let pattern = try #require(StrokeDashPattern(dash: [1, 2], phase: huge))
    let reduced = try #require(
      StrokeDashPattern(dash: [1, 2], phase: huge.truncatingRemainder(dividingBy: 3)))
    let position = huge.truncatingRemainder(dividingBy: 3)
    #expect(!reduced.isOn(at: position))
    do {
      #expect(pattern.isOn(at: huge) == reduced.isOn(at: position))
    }
  }

  @Test func setA589TrimOriginAndDashOriginRemainIndependentAcrossTheTrackSeam() throws {
    // Hypothesis: trim and dash offsets are conflated when the selected interval wraps across the authored track origin.
    let dash = try #require(StrokeDashPattern(dash: [1, 1], phase: 0))
    let mask = StrokeMask(dash: dash, trim: .init(from: 0.25, to: 0.75), origin: 1, trimOrigin: 3)
    // Start at 3, keep distances [2,6): positions [5,8) plus [0,1).
    #expect(mask.isOn(at: 5.25, trackLength: 8))
    #expect(!mask.isOn(at: 6.25, trackLength: 8))
    #expect(mask.isOn(at: 7.25, trackLength: 8))
    #expect(!mask.isOn(at: 0.25, trackLength: 8))
    #expect(!mask.isOn(at: 1.25, trackLength: 8))
  }

  @Test func setA590NearestStrokeSampleUsesPhysicalAspectRatherThanSubpixelDistance() {
    // Hypothesis: nearest-track lookup measures raw subpixel distance and picks the wrong disconnected contour at a tall cell aspect.
    let polylines = [[Point.zero, .init(x: 0.1, y: 0)], [Point(x: 3, y: 3), .init(x: 3.1, y: 3)]]
    let tall = SampledStrokeTrack(polylines: polylines, aspectRatio: 4)
    let short = SampledStrokeTrack(polylines: polylines, aspectRatio: 1)
    #expect(abs(tall.position(nearestToX: 0, y: 3) - 0.05) < 1e-12)
    #expect(short.position(nearestToX: 0, y: 3) == 0)
  }

  @Test func setA591DisconnectedStrokeDashPhaseContinuesWithoutMeasuringTheGap() throws {
    // Hypothesis: disconnected stroke contours either restart the pattern or count the unpainted spatial gap in track length.
    let track = SampledStrokeTrack(
      polylines: [
        [.zero, .init(x: 2, y: 0)], [.init(x: 20, y: 0), .init(x: 22, y: 0)],
      ], aspectRatio: 2)
    #expect(track.length == 2)
    let position = track.position(nearestToX: 20, y: 0)
    #expect(position == 1)
    let dash = try #require(StrokeDashPattern(dash: [1, 1], phase: 0))
    #expect(!StrokeMask(dash: dash).isOn(at: position, trackLength: track.length))
  }

  @Test func setA592AnEmptyTrimSuppressesAZeroLengthButDrawableStroke() {
    // Hypothesis: zero-length track early return bypasses the empty mask after a degenerate path paints its dot.
    let shape = SetAStrokePathShape(value: line(.init(x: 0.5, y: 0.5), .init(x: 0.5, y: 0.5)))
    #expect(ink(rows(shape.stroke(), width: 8, height: 4)) > 0)
    do {
      #expect(ink(rows(shape.trim(from: 0.5, to: 0.5).stroke(), width: 8, height: 4)) == 0)
    }
  }

  @Test func setA593DashGapsPreserveExistingTextInsteadOfPaintingBlankStrokeCells() {
    // Hypothesis: a masked-out stroke cell overwrites lower content with a blank during rectangle stroke rasterization.
    let result = rows(
      ZStack {
        Text("abcdefgh")
        Rectangle().stroke(style: StrokeStyle(dash: [1, 1]))
      }, width: 8, height: 1)
    #expect(result == ["─b─d─f─h"])
  }

  @Test func setA594ExplicitDashPatternOverridesADashedGlyphPalettesImplicitRhythm() {
    // Hypothesis: the legacy palette rhythm is applied in addition to an explicitly authored dash pattern.
    let legacy = StrokeStyle(borderSet: .dashed, dash: [2, 2])
    let explicit = StrokeStyle(borderSet: .single, dash: [2, 2])
    #expect(
      rows(Rectangle().stroke(style: legacy), width: 8, height: 1)
        == rows(Rectangle().stroke(style: explicit), width: 8, height: 1))
    #expect(rows(Rectangle().stroke(style: explicit), width: 8, height: 1) == ["──  ──  "])
  }

  @Test func setA595ChangingOnlyTrimFractionsClearsPreviouslyPaintedOutlineCells() throws {
    // Hypothesis: retained shape damage fails to erase the old untrimmed outline when only the stroke window changes.
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAStroke595"), size: .init(width: 16, height: 8)
    ) {
      SetAStrokeTrimMutationRoot()
    }
    defer { h.shutdown() }
    try h.focusText("Trim outline")
    let before = h.frame
    try h.pressKey(.init(.return))
    #expect(h.frame != before)
    let control = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAStroke595Control"), size: .init(width: 16, height: 8)
    ) { SetAStrokeTrimMutationRoot(trimmed: true) }
    defer { control.shutdown() }
    try control.focusText("Trim outline")
    #expect(h.frame == control.frame)
  }

  @Test func setA596TrimmingAParityFilledPathPreservesItsAuthoredHoleRule() {
    // Hypothesis: TrimmedShape's path conversion silently replaces an authored even-odd fill rule with nonzero winding.
    var path = Path(unit)
    path.addRect(.init(origin: .init(x: 0.25, y: 0.25), size: .init(width: 0.5, height: 0.5)))
    let shape = SetAStrokePathShape(value: path, rule: .evenOdd)
    let original = rows(shape.fill(Color.white), width: 20, height: 10)
    let trimmed = rows(shape.trim(from: 0, to: 0.99).fill(Color.white), width: 20, height: 10)
    #expect(original[5][original[5].index(original[5].startIndex, offsetBy: 10)] == " ")
    withKnownIssue("STUI-991: trimmed fill geometry replaces the authored even-odd rule") {
      #expect(trimmed[5][trimmed[5].index(trimmed[5].startIndex, offsetBy: 10)] == " ")
    }
    #expect(ink(trimmed) > 0)
  }

  @Test func setA597ClipOfAShortTrimUsesTheClosingChordInsteadOfTheOriginalOutline() {
    // Hypothesis: clipShape resolves a trimmed analytic shape through its original geometry and ignores the shortened path.
    let text = Text(
      Array(repeating: String(repeating: "x", count: 12), count: 6).joined(separator: "\n"))
    let clipped = rows(text.clipShape(Rectangle().trim(from: 0, to: 0.5)), width: 12, height: 6)
    #expect(clipped[0].contains("x"))
    #expect(clipped[5].first == " ")
    #expect(clipped[0].last == "x")
    #expect(ink(clipped) > 0 && ink(clipped) < 72)
  }

  @Test func setA598CustomShapeNormalizationAppliesTheParentOffsetExactlyOnce() {
    // Hypothesis: custom shape normalization applies the global parent offset again instead of painting in local coordinates.
    let shape = SetAStrokePathShape(
      value: Path(.init(origin: .zero, size: .init(width: 0.5, height: 1))))
    let local = rows(shape.fill(Color.white), width: 6, height: 3)
    let placed = rows(
      HStack(spacing: 2) {
        Text("LLLL").frame(width: 4, height: 3)
        shape.fill(Color.white).frame(width: 6, height: 3)
      }, width: 12, height: 3)
    #expect(placed.map { String($0.dropFirst(6)) } == local)
    #expect(ink(local) > 0)
  }

  @Test func setA599ClippingAnOffscreenLineMatchesCroppingItsTranslatedLargerCanvas() {
    // Hypothesis: negative subpixel coordinates alter the line error accumulator and shift visible pixels at the clip edge.
    var small = BrailleCanvas(width: 4, height: 3)
    small.line(from: (x: -5, y: -3), to: (x: 10, y: 9))
    var large = BrailleCanvas(width: 10, height: 6)
    large.line(from: (x: 1, y: 1), to: (x: 16, y: 13))
    for y in 0..<12 {
      for x in 0..<8 {
        #expect(pixel(small, x, y) == pixel(large, x + 6, y + 4))
      }
    }
  }

  @Test func setA600EllipseScanlineFillDoesNotDropExactIntegerBoundaryPixels() {
    // Hypothesis: floating scanline rounding erases integer points exactly on an anisotropic ellipse boundary.
    var canvas = BrailleCanvas(width: 12, height: 5)
    canvas.fillEllipse(centerX: 10, centerY: 8, radiusX: 10, radiusY: 5)
    // The 6–8–10 integer triples put both pairs exactly on the ellipse.
    for (x, y) in [(8, 3), (6, 4)] {
      for dx in [-x, x] {
        for dy in [-y, y] {
          let isPainted = pixel(canvas, 10 + dx, 8 + dy)
          if x == 6 {
            withKnownIssue("STUI-992: ellipse scanline flooring drops exact boundary pixels") {
              #expect(isPainted, "Exact ellipse boundary at x=\(10 + dx), y=\(8 + dy)")
            }
          } else {
            #expect(isPainted, "Exact ellipse boundary at x=\(10 + dx), y=\(8 + dy)")
          }
        }
      }
    }
    #expect(!pixel(canvas, 19, 11))
    #expect(pixel(canvas, 10, 8))
  }

  private var unit: Rect { .init(origin: .zero, size: .init(width: 1, height: 1)) }
  private func line(_ a: Point, _ b: Point) -> Path { Path([.move(to: a), .line(to: b)]) }
  private func rows<V: View>(_ view: V, width: Int, height: Int) -> [String] {
    DefaultRenderer().render(
      view.frame(width: width, height: height, alignment: .topLeading),
      context: .init(identity: testIdentity("SetAStroke")),
      proposal: .init(width: width, height: height)
    )
    .rasterSurface.cells.map { String($0.map(\.character)) }
  }
  private func ink(_ rows: [String]) -> Int {
    rows.joined().filter { $0 != " " && $0 != "\u{2800}" }.count
  }
  private func pixel(_ canvas: BrailleCanvas, _ x: Int, _ y: Int) -> Bool {
    canvas.cell(x: x / 2, y: y / 4).contains(x: x % 2, y: y % 4)
  }
}

private struct SetAStrokePathShape: InsettableShape {
  var value: Path
  var rule: FillRule = .nonZero
  var geometry: ShapeGeometry { .path(BoxedPath(value), rule) }
}

private struct SetAStrokeTrimMutationRoot: View {
  @State var trimmed = false
  var body: some View {
    VStack {
      Button("Trim outline") { trimmed.toggle() }
      Rectangle().trim(from: 0, to: trimmed ? 0.25 : 1).stroke().frame(width: 12, height: 5)
    }
  }
}
