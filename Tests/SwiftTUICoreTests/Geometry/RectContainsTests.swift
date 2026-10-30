import SwiftTUICore
import Testing

@Suite("CellRect containment")
struct RectContainsTests {
  @Test(
    "continuous intersection rejects nonfinite geometry in either operand",
    arguments: [Double.nan, .infinity, -.infinity], 0..<4)
  func nonfiniteIntersection(value: Double, component: Int) {
    let valid = Rect(origin: .init(x: 10, y: 10), size: .init(width: 5, height: 5))
    var values = [0.0, 0, 100, 100]
    values[component] = value
    let invalid = Rect(
      origin: .init(x: values[0], y: values[1]),
      size: .init(width: values[2], height: values[3]))
    #expect(valid.intersection(invalid) == nil)
    #expect(invalid.intersection(valid) == nil)
    #expect(valid.intersection(valid) == valid)
    #expect(valid.intersection(.zero) == nil)
  }

  @Test("CellRect contains integer cells with half-open bounds")
  func containsCellsHalfOpen() {
    let rect = CellRect(
      origin: CellPoint(x: 2, y: 3),
      size: CellSize(width: 4, height: 5)
    )

    #expect(rect.contains(CellPoint(x: 2, y: 3)))
    #expect(rect.contains(CellPoint(x: 5, y: 7)))
    #expect(!rect.contains(CellPoint(x: 6, y: 7)))
    #expect(!rect.contains(CellPoint(x: 5, y: 8)))
  }

  @Test("CellRect contains continuous points with half-open bounds")
  func containsContinuousPointsHalfOpen() {
    let rect = CellRect(
      origin: CellPoint(x: 2, y: 3),
      size: CellSize(width: 4, height: 5)
    )

    #expect(rect.contains(Point(x: 2.0, y: 3.0)))
    #expect(rect.contains(Point(x: 5.999, y: 7.999)))
    #expect(!rect.contains(Point(x: 6.0, y: 7.999)))
    #expect(!rect.contains(Point(x: 5.999, y: 8.0)))
  }

  @Test("Empty CellRect contains no cells or points")
  func emptyRectContainsNothing() {
    let rect = CellRect(
      origin: CellPoint(x: 2, y: 3),
      size: CellSize(width: 0, height: 5)
    )

    #expect(!rect.contains(CellPoint(x: 2, y: 3)))
    #expect(!rect.contains(Point(x: 2.0, y: 3.0)))
  }
}
