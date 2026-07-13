import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI raster and geometry stress behavior", .serialized)
struct FrameworkStressRasterGeometryTests {
  @Test("stress raster geometry 001 negative-origin clip intersection stays half-open")
  func rasterGeometry001NegativeOriginClipIntersectionStaysHalfOpen() {
    // Hypothesis: translating both clips through negative cell space can introduce a one-cell
    // expansion when their half-open bounds are intersected.
    let rasterizer = Rasterizer()
    let lhs = CellRect(
      origin: CellPoint(x: -7, y: -5),
      size: CellSize(width: 10, height: 8)
    )
    let rhs = CellRect(
      origin: CellPoint(x: -3, y: -8),
      size: CellSize(width: 9, height: 7)
    )

    #expect(
      rasterizer.intersect(lhs, rhs)
        == CellRect(
          origin: CellPoint(x: -3, y: -5),
          size: CellSize(width: 6, height: 4)
        )
    )
  }

  @Test("stress raster geometry 002 edge-touching clips have no raster area")
  func rasterGeometry002EdgeTouchingClipsHaveNoRasterArea() {
    // Hypothesis: touching trailing and leading edges can be mistaken for a one-column overlap.
    let rasterizer = Rasterizer()
    let lhs = CellRect(origin: .zero, size: CellSize(width: 5, height: 4))
    let rhs = CellRect(origin: CellPoint(x: 5, y: 1), size: CellSize(width: 3, height: 2))

    #expect(rasterizer.intersect(lhs, rhs) == nil)
  }

  @Test("stress raster geometry 003 contained clip preserves the inner origin and extent")
  func rasterGeometry003ContainedClipPreservesInnerOriginAndExtent() {
    // Hypothesis: intersecting a negative outer clip with a positive inner clip can incorrectly
    // normalize the inner origin back to zero.
    let rasterizer = Rasterizer()
    let outer = CellRect(
      origin: CellPoint(x: -20, y: -20),
      size: CellSize(width: 50, height: 50)
    )
    let inner = CellRect(
      origin: CellPoint(x: 7, y: 9),
      size: CellSize(width: 4, height: 3)
    )

    #expect(rasterizer.intersect(outer, inner) == inner)
  }

  @Test("stress raster geometry 004 nested clip intersection is associative")
  func rasterGeometry004NestedClipIntersectionIsAssociative() throws {
    // Hypothesis: successive ancestor clips can lose a boundary depending on traversal order.
    let rasterizer = Rasterizer()
    let a = CellRect(origin: CellPoint(x: -4, y: -3), size: CellSize(width: 16, height: 12))
    let b = CellRect(origin: CellPoint(x: 1, y: -5), size: CellSize(width: 8, height: 15))
    let c = CellRect(origin: CellPoint(x: -1, y: 2), size: CellSize(width: 7, height: 4))

    let ab = try #require(rasterizer.intersect(a, b))
    let bc = try #require(rasterizer.intersect(b, c))
    #expect(rasterizer.intersect(ab, c) == rasterizer.intersect(a, bc))
  }

  @Test("stress raster geometry 005 clipped wide glyph rejection is atomic")
  func rasterGeometry005ClippedWideGlyphRejectionIsAtomic() {
    // Hypothesis: rejecting a wide glyph whose continuation crosses the clip can still clear or
    // overwrite its in-clip lead cell.
    let rasterizer = Rasterizer()
    var cells = [
      [
        RasterCell(character: "a"),
        RasterCell(character: "b"),
        RasterCell(character: "c"),
      ]
    ]
    let original = cells

    rasterizer.write(
      "界",
      width: 2,
      atX: 1,
      y: 0,
      cells: &cells,
      clip: CellRect(origin: .zero, size: CellSize(width: 2, height: 1))
    )

    #expect(cells == original)
  }

  @Test("stress raster geometry 006 wide glyph ending at clip edge keeps its continuation")
  func rasterGeometry006WideGlyphEndingAtClipEdgeKeepsItsContinuation() {
    // Hypothesis: the half-open trailing-edge check can reject a wide glyph that ends exactly at
    // the clip boundary or omit its continuation metadata.
    let rasterizer = Rasterizer()
    var cells = [[RasterCell.empty, RasterCell.empty, RasterCell.empty]]

    rasterizer.write(
      "界",
      width: 2,
      atX: 1,
      y: 0,
      cells: &cells,
      clip: CellRect(origin: .zero, size: CellSize(width: 3, height: 1))
    )

    #expect(cells[0][1].character == "界")
    #expect(cells[0][1].spanWidth == 2)
    #expect(cells[0][2].continuationLeadX == 1)
  }

  @Test("stress raster geometry 007 tint outside clip leaves every pixel untouched")
  func rasterGeometry007TintOutsideClipLeavesEveryPixelUntouched() {
    // Hypothesis: the translucent tint path can apply bounds checks without applying the active
    // clip, leaking color into a neighboring cell.
    let rasterizer = Rasterizer()
    var cells = [
      [
        RasterCell(style: ResolvedTextStyle(backgroundColor: .blue)),
        RasterCell(style: ResolvedTextStyle(backgroundColor: .green)),
      ]
    ]
    let original = cells

    rasterizer.tintCell(
      atX: 1,
      y: 0,
      with: Color.red.opacity(0.5),
      cells: &cells,
      clip: CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    )

    #expect(cells == original)
  }

  @Test("stress raster geometry 008 tint changes only the addressed in-clip pixel")
  func rasterGeometry008TintChangesOnlyTheAddressedInClipPixel() {
    // Hypothesis: in-place tinting can accidentally reuse a row buffer and color adjacent cells.
    let rasterizer = Rasterizer()
    var cells = [[RasterCell.empty, RasterCell.empty, RasterCell.empty]]

    rasterizer.tintCell(
      atX: 1,
      y: 0,
      with: Color.red.opacity(0.25),
      cells: &cells,
      clip: CellRect(origin: .zero, size: CellSize(width: 3, height: 1))
    )

    #expect(cells[0][0] == .empty)
    #expect(cells[0][1].style?.backgroundColor == Color.red.opacity(0.25))
    #expect(cells[0][2] == .empty)
  }

  @Test("stress raster geometry 009 empty linear gradient samples transparent")
  func rasterGeometry009EmptyLinearGradientSamplesTransparent() {
    // Hypothesis: sampling an empty gradient can read a nonexistent stop or synthesize a default
    // terminal color at a raster boundary.
    let gradient = LinearGradient(
      gradient: Gradient(stops: []),
      startPoint: .leading,
      endPoint: .trailing
    )

    #expect(
      Rasterizer().sample(
        gradient,
        in: CellRect(origin: .zero, size: CellSize(width: 7, height: 3)),
        x: 6,
        y: 2
      ) == nil
    )
  }

  @Test("stress raster geometry 010 one-stop linear gradient is uniform beyond both edges")
  func rasterGeometry010OneStopLinearGradientIsUniformBeyondBothEdges() {
    // Hypothesis: the one-stop fast path can still project out-of-bounds sample coordinates and
    // lose the only authored color.
    let gradient = LinearGradient(colors: [.magenta], startPoint: .leading, endPoint: .trailing)
    let bounds = CellRect(origin: CellPoint(x: 4, y: 2), size: CellSize(width: 5, height: 2))
    let rasterizer = Rasterizer()

    #expect(rasterizer.sample(gradient, in: bounds, x: -100, y: 2) == .magenta)
    #expect(rasterizer.sample(gradient, in: bounds, x: 100, y: 3) == .magenta)
  }

  @Test("stress raster geometry 011 coincident linear endpoints pin to first stop")
  func rasterGeometry011CoincidentLinearEndpointsPinToFirstStop() {
    // Hypothesis: a zero-length gradient axis can divide by zero and produce a non-deterministic
    // stop selection across cells.
    let gradient = LinearGradient(colors: [.yellow, .blue], startPoint: .center, endPoint: .center)
    let bounds = CellRect(origin: .zero, size: CellSize(width: 12, height: 5))
    let rasterizer = Rasterizer()

    #expect(rasterizer.sample(gradient, in: bounds, x: 0, y: 0) == .yellow)
    #expect(rasterizer.sample(gradient, in: bounds, x: 11, y: 4) == .yellow)
  }

  @Test("stress raster geometry 012 reversed linear axis mirrors edge samples")
  func rasterGeometry012ReversedLinearAxisMirrorsEdgeSamples() {
    // Hypothesis: reversing gradient endpoints can clamp against the unreversed axis and make the
    // two edge colors asymmetric.
    let forward = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let reverse = LinearGradient(colors: [.red, .blue], startPoint: .trailing, endPoint: .leading)
    let bounds = CellRect(origin: .zero, size: CellSize(width: 10, height: 1))
    let rasterizer = Rasterizer()

    #expect(
      rasterizer.sample(forward, in: bounds, x: 0, y: 0)
        == rasterizer.sample(reverse, in: bounds, x: 9, y: 0)
    )
    #expect(
      rasterizer.sample(forward, in: bounds, x: 9, y: 0)
        == rasterizer.sample(reverse, in: bounds, x: 0, y: 0)
    )
  }

  @Test("stress raster geometry 013 duplicate gradient location has deterministic boundary color")
  func rasterGeometry013DuplicateGradientLocationHasDeterministicBoundaryColor() {
    // Hypothesis: equal-location stops can hit a zero-width interpolation segment and select a
    // different color depending on sort or floating-point behavior.
    let gradient = LinearGradient(
      gradient: Gradient(stops: [
        .init(color: .red, location: 0),
        .init(color: .green, location: 0.5),
        .init(color: .blue, location: 0.5),
        .init(color: .white, location: 1),
      ]),
      startPoint: .leading,
      endPoint: .trailing
    )

    #expect(
      rasterGeometryColorsApproximatelyEqual(
        Rasterizer().sample(
          gradient,
          in: CellRect(origin: .zero, size: CellSize(width: 1, height: 1)),
          x: 0,
          y: 0
        ),
        .green
      )
    )
  }

  @Test("stress raster geometry 014 gradient stop locations clamp before sorting")
  func rasterGeometry014GradientStopLocationsClampBeforeSorting() {
    // Hypothesis: sorting raw out-of-range locations before clamping can leave endpoint stops in an
    // order that no longer matches their effective raster locations.
    let gradient = Gradient(stops: [
      .init(color: .blue, location: 4),
      .init(color: .red, location: -3),
      .init(color: .green, location: 0.25),
    ])

    #expect(gradient.stops.map(\.location) == [0, 0.25, 1])
    #expect(gradient.stops.map(\.color) == [.red, .green, .blue])
  }

  @Test("stress raster geometry 015 empty radial gradient samples transparent")
  func rasterGeometry015EmptyRadialGradientSamplesTransparent() {
    // Hypothesis: the radial sampler can enter radius normalization before noticing that no stop
    // exists, manufacturing a color or trapping on degenerate input.
    let gradient = RadialGradient(
      gradient: Gradient(stops: []),
      center: .center,
      startRadius: 2,
      endRadius: 2
    )

    #expect(
      Rasterizer().sample(
        gradient,
        in: CellRect(origin: .zero, size: CellSize(width: 9, height: 9)),
        x: 4,
        y: 4
      ) == nil
    )
  }

  @Test("stress raster geometry 016 radial inner radius preserves first stop")
  func rasterGeometry016RadialInnerRadiusPreservesFirstStop() {
    // Hypothesis: cell-center sampling near the gradient center can subtract startRadius with the
    // wrong sign and jump into the interpolation band.
    let gradient = RadialGradient(
      colors: [.red, .blue],
      center: .center,
      startRadius: 3,
      endRadius: 5
    )
    let bounds = CellRect(origin: .zero, size: CellSize(width: 10, height: 10))

    #expect(Rasterizer().sample(gradient, in: bounds, x: 4, y: 4) == .red)
  }

  @Test("stress raster geometry 017 radial samples beyond end radius clamp to last stop")
  func rasterGeometry017RadialSamplesBeyondEndRadiusClampToLastStop() {
    // Hypothesis: a center near the opposite corner can leave distances above endRadius
    // unbounded, causing extrapolated color components instead of the terminal stop.
    let gradient = RadialGradient(
      colors: [.yellow, .blue],
      center: .topLeading,
      startRadius: 0,
      endRadius: 2
    )
    let bounds = CellRect(origin: .zero, size: CellSize(width: 10, height: 10))

    #expect(Rasterizer().sample(gradient, in: bounds, x: 9, y: 9) == .blue)
  }

  @Test("stress raster geometry 018 open path fill closes only for rasterization")
  func rasterGeometry018OpenPathFillClosesOnlyForRasterization() {
    // Hypothesis: the scanline fill can forget its documented implicit close and leave an open
    // polygon with a different silhouette from the equivalent explicit path.
    let open = rasterGeometryUnitSquare(closed: false)
    let closed = rasterGeometryUnitSquare(closed: true)
    let openFrame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: open).fill(Color.white).frame(width: 11, height: 5),
      identity: "RasterGeometry018Open"
    )
    let closedFrame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: closed).fill(Color.white).frame(width: 11, height: 5),
      identity: "RasterGeometry018Closed"
    )

    #expect(openFrame.rasterSurface == closedFrame.rasterSurface)
  }

  @Test("stress raster geometry 019 collinear closed path paints no fill pixels")
  func rasterGeometry019CollinearClosedPathPaintsNoFillPixels() {
    // Hypothesis: duplicate scanline crossings from a zero-area closed path can create a phantom
    // one-subpixel fill span.
    var path = Path()
    path.move(to: Point(x: 0, y: 0.5))
    path.addLine(to: Point(x: 0.5, y: 0.5))
    path.addLine(to: Point(x: 1, y: 0.5))
    path.close()
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: path).fill(Color.white).frame(width: 13, height: 5),
      identity: "RasterGeometry019"
    )

    #expect(rasterGeometryLitDotCount(frame) == 0)
  }

  @Test("stress raster geometry 020 same-winding nested path keeps center filled")
  func rasterGeometry020SameWindingNestedPathKeepsCenterFilled() {
    // Hypothesis: the non-zero scanline accumulator can accidentally toggle like even-odd when
    // two same-direction subpaths overlap.
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: rasterGeometryNestedSquares(innerReversed: false))
        .fill(Color.white)
        .frame(width: 16, height: 8),
      identity: "RasterGeometry020"
    )

    #expect(rasterGeometryDotCount(frame.rasterSurface.cells[4][8]) > 0)
  }

  @Test("stress raster geometry 021 opposite-winding non-zero path preserves center hole")
  func rasterGeometry021OppositeWindingNonZeroPathPreservesCenterHole() {
    // Hypothesis: sorting crossings without retaining direction can make non-zero filling ignore
    // an oppositely wound inner contour.
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: rasterGeometryNestedSquares(innerReversed: true))
        .fill(Color.white)
        .frame(width: 16, height: 8),
      identity: "RasterGeometry021"
    )

    #expect(rasterGeometryDotCount(frame.rasterSurface.cells[4][8]) == 0)
    #expect(rasterGeometryLitDotCount(frame) > 0)
  }

  @Test("stress raster geometry 022 even-odd path removes same-winding center")
  func rasterGeometry022EvenOddPathRemovesSameWindingCenter() {
    // Hypothesis: even-odd filling can accidentally reuse signed winding state and fill a hole
    // whose two contours share the same direction.
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(
        pathValue: rasterGeometryNestedSquares(innerReversed: false),
        rule: .evenOdd
      )
      .fill(Color.white)
      .frame(width: 16, height: 8),
      identity: "RasterGeometry022"
    )

    #expect(rasterGeometryDotCount(frame.rasterSurface.cells[4][8]) == 0)
    #expect(rasterGeometryLitDotCount(frame) > 0)
  }

  @Test("stress raster geometry 023 oversized normalized path clips to its frame")
  func rasterGeometry023OversizedNormalizedPathClipsToItsFrame() {
    // Hypothesis: scanline spans from path coordinates outside the unit square can write beyond
    // the Braille canvas or leave the frame edges partially unfilled.
    var path = Path()
    path.addRect(Rect(origin: Point(x: -1, y: -1), size: Size(width: 3, height: 3)))
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: path).fill(Color.white).frame(width: 7, height: 3),
      identity: "RasterGeometry023"
    )

    #expect(frame.rasterSurface.size == CellSize(width: 7, height: 3))
    #expect(
      frame.rasterSurface.cells.allSatisfy { row in
        row.allSatisfy { $0.character == "\u{28FF}" }
      })
  }

  @Test("stress raster geometry 024 one-cell boundary stroke remains visible")
  func rasterGeometry024OneCellBoundaryStrokeRemainsVisible() {
    // Hypothesis: mapping unit-1 path coordinates onto an inclusive 1x1 Braille grid can collapse
    // every segment off-grid and erase the entire stroke.
    let frame = rasterGeometryRender(
      RasterGeometryPathShape(pathValue: rasterGeometryUnitSquare(closed: true))
        .stroke(Color.white)
        .frame(width: 1, height: 1),
      identity: "RasterGeometry024"
    )

    #expect(rasterGeometryDotCount(frame.rasterSurface.cells[0][0]) > 0)
  }

  @Test("stress raster geometry 025 retained circle follows cell-pixel metric churn")
  func rasterGeometry025RetainedCircleFollowsCellPixelMetricChurn() {
    // Hypothesis: raster reuse can key a curved-shape mask by cell bounds only, preserving an old
    // aspect correction after terminal pixel metrics change.
    let renderer = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache()))
    let identity = testIdentity("RasterGeometry025")
    let metrics = [
      CellPixelMetrics.estimated,
      CellPixelMetrics(width: 12, height: 16, source: .reported),
      CellPixelMetrics(width: 6, height: 14, source: .reported),
    ]

    for generation in 0..<15 {
      var environment = EnvironmentValues()
      environment.cellPixelMetrics = metrics[generation % metrics.count]
      let view = Circle().fill(Color.white).frame(width: 10, height: 6)
      let retained = renderer.render(
        view,
        context: .init(
          identity: identity,
          environmentValues: environment,
          invalidatedIdentities: generation == 0 ? [] : [identity]
        )
      )
      let fresh = DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
        view,
        context: .init(identity: identity, environmentValues: environment)
      )

      #expect(retained.rasterSurface == fresh.rasterSurface)
      #expect(rasterGeometryLitDotCount(retained) > 0)
    }
  }
}

private struct RasterGeometryPathShape: InsettableShape {
  let pathValue: Path
  var rule: FillRule = .nonZero

  var geometry: ShapeGeometry {
    .path(BoxedPath(pathValue), rule)
  }
}

@MainActor
private func rasterGeometryRender<Content: View>(
  _ view: Content,
  identity: String
) -> RenderSnapshot {
  DefaultRenderer(layoutEngine: .init(cache: MeasurementCache())).render(
    view,
    context: .init(identity: testIdentity(identity))
  )
}

private func rasterGeometryDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

private func rasterGeometryLitDotCount(_ frame: RenderSnapshot) -> Int {
  frame.rasterSurface.cells.reduce(into: 0) { count, row in
    count += row.reduce(into: 0) { $0 += rasterGeometryDotCount($1) }
  }
}

private func rasterGeometryColorsApproximatelyEqual(
  _ lhs: Color?,
  _ rhs: Color,
  tolerance: Double = 0.000_001
) -> Bool {
  guard let lhs else {
    return false
  }
  return abs(lhs.red - rhs.red) <= tolerance
    && abs(lhs.green - rhs.green) <= tolerance
    && abs(lhs.blue - rhs.blue) <= tolerance
    && abs(lhs.alpha - rhs.alpha) <= tolerance
    && lhs.profile == rhs.profile
}

private func rasterGeometryUnitSquare(closed: Bool) -> Path {
  var path = Path()
  path.move(to: Point(x: 0, y: 0))
  path.addLine(to: Point(x: 1, y: 0))
  path.addLine(to: Point(x: 1, y: 1))
  path.addLine(to: Point(x: 0, y: 1))
  if closed {
    path.close()
  }
  return path
}

private func rasterGeometryNestedSquares(innerReversed: Bool) -> Path {
  var path = rasterGeometryUnitSquare(closed: true)
  path.move(to: Point(x: 0.25, y: 0.25))
  if innerReversed {
    path.addLine(to: Point(x: 0.25, y: 0.75))
    path.addLine(to: Point(x: 0.75, y: 0.75))
    path.addLine(to: Point(x: 0.75, y: 0.25))
  } else {
    path.addLine(to: Point(x: 0.75, y: 0.25))
    path.addLine(to: Point(x: 0.75, y: 0.75))
    path.addLine(to: Point(x: 0.25, y: 0.75))
  }
  path.close()
  return path
}
