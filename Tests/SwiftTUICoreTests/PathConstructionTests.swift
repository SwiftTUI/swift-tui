import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Path construction, fill rules, and flattening")
struct PathConstructionTests {

  // MARK: - Fill rules

  /// A pentagram (the star polygon {5/2}) has winding number 2 at its center,
  /// so the center is INSIDE under `.nonZero` but OUTSIDE under `.evenOdd`.
  private func pentagram() -> Path {
    // Regular pentagon vertices on the unit circle, connected every-other.
    let v0 = Point(x: 0, y: -1)
    let v1 = Point(x: 0.951, y: -0.309)
    let v2 = Point(x: 0.588, y: 0.809)
    let v3 = Point(x: -0.588, y: 0.809)
    let v4 = Point(x: -0.951, y: -0.309)
    var path = Path()
    path.move(to: v0)
    path.addLine(to: v2)
    path.addLine(to: v4)
    path.addLine(to: v1)
    path.addLine(to: v3)
    path.close()
    return path
  }

  @Test("pentagram center is inside under nonZero, outside under evenOdd")
  func pentagramWindingRules() {
    let star = pentagram()
    let center = Point(x: 0, y: 0)
    #expect(star.contains(center, fillRule: .nonZero) == true)
    #expect(star.contains(center, fillRule: .evenOdd) == false)
  }

  @Test("points far outside are excluded under both rules")
  func pointsOutside() {
    let star = pentagram()
    let far = Point(x: 10, y: 10)
    #expect(star.contains(far, fillRule: .nonZero) == false)
    #expect(star.contains(far, fillRule: .evenOdd) == false)
  }

  @Test("contains defaults to evenOdd (preserves legacy hit-test behavior)")
  func containsDefaultIsEvenOdd() {
    let star = pentagram()
    let center = Point(x: 0, y: 0)
    // The no-argument form must equal the explicit even-odd form.
    #expect(star.contains(center) == star.contains(center, fillRule: .evenOdd))
  }

  @Test("a simple convex square contains its center and excludes outside")
  func convexSquare() {
    let square = Path(Rect(origin: Point(x: 0, y: 0), size: Size(width: 10, height: 10)))
    #expect(square.contains(Point(x: 5, y: 5)) == true)
    #expect(square.contains(Point(x: 5, y: 5), fillRule: .nonZero) == true)
    #expect(square.contains(Point(x: 15, y: 5)) == false)
  }

  // MARK: - Flattening

  @Test("a straight cubic flattens to a single segment")
  func straightCubicFlattens() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    // Control points colinear with the endpoints.
    path.addCurve(
      to: Point(x: 9, y: 0),
      control1: Point(x: 3, y: 0),
      control2: Point(x: 6, y: 0))
    let polylines = path.flattened(tolerance: 0.1)
    #expect(polylines.count == 1)
    #expect(polylines[0] == [Point(x: 0, y: 0), Point(x: 9, y: 0)])
  }

  @Test("a curved cubic flattens to many monotone-spaced points")
  func curvedCubicFlattens() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addCurve(
      to: Point(x: 10, y: 0),
      control1: Point(x: 0, y: 10),
      control2: Point(x: 10, y: 10))
    let polylines = path.flattened(tolerance: 0.1)
    #expect(polylines.count == 1)
    // A real curve must subdivide well past the two endpoints.
    #expect(polylines[0].count > 4)
    #expect(polylines[0].first == Point(x: 0, y: 0))
    #expect(polylines[0].last == Point(x: 10, y: 0))
  }

  @Test("a quad curve flattens and finer tolerance yields more points")
  func quadToleranceMonotonic() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addQuadCurve(to: Point(x: 10, y: 0), control: Point(x: 5, y: 10))
    let coarse = path.flattened(tolerance: 1.0)[0].count
    let fine = path.flattened(tolerance: 0.05)[0].count
    #expect(fine >= coarse)
    #expect(fine > 2)
  }

  @Test("an explicitly closed subpath repeats its start; an open one does not")
  func flattenedClosure() {
    var closed = Path()
    closed.move(to: Point(x: 0, y: 0))
    closed.addLine(to: Point(x: 10, y: 0))
    closed.addLine(to: Point(x: 10, y: 10))
    closed.close()
    let closedPoly = closed.flattened()[0]
    #expect(closedPoly.first == closedPoly.last)

    var open = Path()
    open.move(to: Point(x: 0, y: 0))
    open.addLine(to: Point(x: 10, y: 0))
    open.addLine(to: Point(x: 10, y: 10))
    let openPoly = open.flattened()[0]
    #expect(openPoly.first != openPoly.last)
  }

  // MARK: - Constructors

  @Test("addEllipse boundingRect equals the inscribing rect")
  func ellipseBoundingRect() {
    let rect = Rect(origin: Point(x: 2, y: 3), size: Size(width: 10, height: 6))
    let ellipse = Path(ellipseIn: rect)
    let bounds = ellipse.boundingRect
    #expect(bounds != nil)
    guard let bounds else { return }
    #expect(abs(bounds.origin.x - 2) < 0.001)
    #expect(abs(bounds.origin.y - 3) < 0.001)
    #expect(abs(bounds.maxX - 12) < 0.001)
    #expect(abs(bounds.maxY - 9) < 0.001)
  }

  @Test("closeSubpath is an exact alias for close")
  func closeSubpathAlias() {
    var a = Path()
    a.move(to: Point(x: 0, y: 0))
    a.addLine(to: Point(x: 1, y: 1))
    a.close()
    var b = Path()
    b.move(to: Point(x: 0, y: 0))
    b.addLine(to: Point(x: 1, y: 1))
    b.closeSubpath()
    #expect(a == b)
  }

  @Test("rounded rect with zero radius equals a plain rect")
  func roundedRectZeroRadius() {
    let rect = Rect(origin: Point(x: 0, y: 0), size: Size(width: 8, height: 4))
    let rounded = Path(roundedRect: rect, cornerRadius: 0)
    #expect(rounded == Path(rect))
  }

  @Test("init(_:build:) composes the same elements as imperative building")
  func builderInit() {
    let built = Path { path in
      path.move(to: Point(x: 0, y: 0))
      path.addLine(to: Point(x: 4, y: 0))
      path.close()
    }
    var manual = Path()
    manual.move(to: Point(x: 0, y: 0))
    manual.addLine(to: Point(x: 4, y: 0))
    manual.close()
    #expect(built == manual)
  }
}
