import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("LineChart domain helpers")
struct LineChartDomainTests {
  @Test("LineChartPoint stores raw x and y")
  func storesRawCoords() {
    let point = LineChartPoint(x: 3.5, y: 12)
    #expect(point.x == 3.5)
    #expect(point.y == 12)
  }

  @Test("LineChartPoint date initializer maps to reference interval")
  func dateInitializerMapsToReferenceInterval() {
    let date = Date(timeIntervalSinceReferenceDate: 123_456)
    let point = LineChartPoint(date: date, value: 9)
    #expect(point.x == 123_456)
    #expect(point.y == 9)
  }
}
