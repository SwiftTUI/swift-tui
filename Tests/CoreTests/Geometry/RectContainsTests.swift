import Core
import Testing

@Suite("CellRect containment")
struct RectContainsTests {
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
