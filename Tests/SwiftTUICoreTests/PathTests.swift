import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct PathTests {
  @Test("leading lines render and hit-test from the implicit origin")
  func leadingLines() {
    let endpoint = Point(x: 4, y: 4)
    let line = Path { $0.addLine(to: endpoint) }
    #expect(line.flattened() == [[.zero, endpoint]])
    #expect(line.boundingRect?.origin == .zero)

    let square = Path {
      $0.addLine(to: Point(x: 4, y: 0))
      $0.addLine(to: endpoint)
      $0.addLine(to: Point(x: 0, y: 4))
      $0.close()
    }
    let explicit = Path([.move(to: .zero)] + square.elements)
    #expect(square.flattened() == explicit.flattened())
    #expect(square.boundingRect == explicit.boundingRect)
    // This corner is excluded if the implicit origin is lost and the square
    // becomes a triangle.
    #expect(square.contains(Point(x: 0.5, y: 0.5)))
  }

  @Test("explicit moves and closed-subpath continuations retain their own origin")
  func lineOriginsAfterMoveAndClose() {
    let start = Point(x: 3, y: 3)
    let end = Point(x: 5, y: 5)
    var path = Path {
      $0.move(to: start)
      $0.addLine(to: end)
    }
    #expect(path.flattened() == [[start, end]])
    #expect(path.boundingRect?.origin == start)
    path.close()
    path.addLine(to: Point(x: 7, y: 3))
    #expect(path.flattened() == [[start, end, start], [start, Point(x: 7, y: 3)]])
  }

  @Test(
    "leading curves include their implicit origin in the coarse hit bounds",
    arguments: [false, true])
  func leadingCurveBounds(cubic: Bool) throws {
    var path = Path()
    if cubic {
      path.addCurve(to: Point(x: 8, y: 8), control1: Point(x: 8, y: 2), control2: Point(x: 8, y: 4))
    } else {
      path.addQuadCurve(to: Point(x: 8, y: 8), control: Point(x: 8, y: 2))
    }
    path.close()
    let bounds = try #require(path.boundingRect)
    #expect(bounds.origin == .zero)
    #expect(path.contains(Point(x: 2, y: 1)))
  }

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
