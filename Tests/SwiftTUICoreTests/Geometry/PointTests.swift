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

  @Test("Point cell conversions saturate at half the Int range and map NaN to its lower bound")
  func pointCellConversionsSaturate() async {
    await #expect(processExitsWith: .success) {
      #expect(Point(x: .nan, y: 1.5).containingCell == CellPoint(x: Int.min / 2, y: 1))
      #expect(
        Point(x: 1e300, y: -1e300).containingCell == CellPoint(x: Int.max / 2, y: Int.min / 2))
      #expect(
        Point(x: .infinity, y: .nan).snapped(.toNearestOrEven)
          == CellPoint(x: Int.max / 2, y: Int.min / 2))
      #expect(
        Point(x: -.infinity, y: 2.5).snapped(.toNearestOrEven) == CellPoint(x: Int.min / 2, y: 2))
    }
  }

  @Test("Point cell conversions inside the saturation bound are unchanged")
  func pointCellConversionsInsideTheBound() {
    let largest = Double(Int.max / 2).nextDown
    #expect(
      Point(x: largest, y: -largest).containingCell == CellPoint(x: Int(largest), y: Int(-largest)))
    #expect(Point(x: -2.5, y: 2.5).snapped(.toNearestOrEven) == CellPoint(x: -2, y: 2))
    #expect(Point(x: -0.5, y: 2.9999999999999996).containingCell == CellPoint(x: -1, y: 2))
  }
}
