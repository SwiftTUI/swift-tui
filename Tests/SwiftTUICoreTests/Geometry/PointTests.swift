import SwiftTUICore
import Testing

@Suite("Continuous geometry")
struct PointTests {
  @Test("Point, Size, Rect, and Vector preserve fractional cell values")
  func continuousGeometryPreservesFractions() {
    let point = Point(x: 1.25, y: 2.75)
    let size = Size(width: 3.5, height: 4.125)
    let vector = Vector(dx: -0.5, dy: 0.25)
    let rect = Rect(origin: point, size: size)

    #expect(point.x == 1.25)
    #expect(point.y == 2.75)
    #expect(size.width == 3.5)
    #expect(size.height == 4.125)
    #expect(vector.dx == -0.5)
    #expect(vector.dy == 0.25)
    #expect(rect.maxX == 4.75)
    #expect(rect.maxY == 6.875)
  }

  @Test("Point projects to containing cell and in-cell fraction")
  func pointProjectsToCellGeometry() {
    let point = Point(x: 4.75, y: 8.125)

    #expect(point.containingCell == CellPoint(x: 4, y: 8))
    #expect(point.fractionInCell == UnitPoint(x: 0.75, y: 0.125))
    #expect(point.snapped(.down) == CellPoint(x: 4, y: 8))
    #expect(point.snapped(.up) == CellPoint(x: 5, y: 9))
  }

  @Test("Point conversion from CellPoint uses the cell origin")
  func pointInitializesFromCellPoint() {
    #expect(Point(CellPoint(x: 3, y: 5)) == Point(x: 3.0, y: 5.0))
  }
}
