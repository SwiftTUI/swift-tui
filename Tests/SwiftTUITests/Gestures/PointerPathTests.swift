import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

@Suite("PointerPath")
struct PointerPathTests {
  @Test("PointerPath is an ordered random-access collection")
  func orderedRandomAccessCollection() {
    let firstPointer = PointerLocation.subCell(
      location: Point(x: 1.25, y: 2.5),
      source: .nativePixels,
      metrics: .estimated,
      rawPixel: PixelPoint(x: 10, y: 40)
    )
    let secondPointer = PointerLocation.subCell(
      location: Point(x: 1.75, y: 2.5),
      source: .nativePixels,
      metrics: .estimated,
      rawPixel: PixelPoint(x: 14, y: 40)
    )
    let firstTime = MonotonicInstant.now()
    let secondTime = firstTime.advanced(by: .milliseconds(8))
    let path = PointerPath([
      PointerPath.Sample(
        location: firstPointer.location,
        time: firstTime,
        pointer: firstPointer
      ),
      PointerPath.Sample(
        location: secondPointer.location,
        time: secondTime,
        pointer: secondPointer
      ),
    ])

    #expect(path.count == 2)
    #expect(path[path.startIndex].location == Point(x: 1.25, y: 2.5))
    #expect(path[path.index(after: path.startIndex)].time == secondTime)
    #expect(
      path.map(\.pointer.rawPixel) == [
        PixelPoint(x: 10, y: 40),
        PixelPoint(x: 14, y: 40),
      ])
  }
}
