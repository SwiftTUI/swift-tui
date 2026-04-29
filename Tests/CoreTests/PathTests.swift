import Testing

@testable import Core

@Suite
struct PathTests {
  @Test("closed polygon contains interior and boundary points")
  func closedPolygonContainsInteriorAndBoundary() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 4, y: 0))
    path.addLine(to: Point(x: 4, y: 3))
    path.addLine(to: Point(x: 0, y: 3))
    path.close()

    #expect(path.contains(Point(x: 2, y: 1.5)))
    #expect(path.contains(Point(x: 4, y: 1)))
    #expect(!path.contains(Point(x: 4.5, y: 1)))
  }

  @Test("translated path preserves hit testing in global coordinates")
  func translatedPath() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0))
    path.addLine(to: Point(x: 2, y: 0))
    path.addLine(to: Point(x: 2, y: 2))
    path.addLine(to: Point(x: 0, y: 2))
    path.close()

    let translated = path.translatedBy(dx: 5, dy: 3)
    #expect(translated.contains(Point(x: 6, y: 4)))
    #expect(!translated.contains(Point(x: 1, y: 1)))
  }
}
