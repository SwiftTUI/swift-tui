import Core
import Testing

@Suite("Cell geometry")
struct CellGeometryTests {
  @Test("Cell geometry stores integer terminal cell values")
  func cellGeometryStoresIntegers() {
    let origin = CellPoint(x: 2, y: 3)
    let size = CellSize(width: 4, height: 5)
    let rect = CellRect(origin: origin, size: size)

    #expect(origin.x == 2)
    #expect(origin.y == 3)
    #expect(size.width == 4)
    #expect(size.height == 5)
    #expect(rect.maxX == 6)
    #expect(rect.maxY == 8)
  }

  @Test("CellRect converts to continuous Rect")
  func cellRectConvertsToContinuousRect() {
    let rect = CellRect(
      origin: CellPoint(x: 2, y: 3),
      size: CellSize(width: 4, height: 5)
    )

    #expect(
      rect.continuous
        == Rect(
          origin: Point(x: 2.0, y: 3.0),
          size: Size(width: 4.0, height: 5.0)
        )
    )
  }
}
