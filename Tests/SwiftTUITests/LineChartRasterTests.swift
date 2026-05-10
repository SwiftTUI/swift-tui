import Foundation
import Testing

@testable import SwiftTUICharts
@testable import SwiftTUICore

@Suite("LineChart raster helpers")
struct LineChartCellMappingTests {
  @Test("xCell maps lower bound to column 0")
  func xLower() {
    #expect(xCell(value: 0, domain: 0...10, plotWidth: 10) == 0)
  }

  @Test("xCell maps upper bound to last column")
  func xUpper() {
    #expect(xCell(value: 10, domain: 0...10, plotWidth: 10) == 9)
  }

  @Test("yCell inverts Y axis (top row = max)")
  func yInverts() {
    #expect(yCell(value: 10, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: 0,  domain: 0...10, plotHeight: 10) == 9)
  }

  @Test("yCell clamps out-of-range to nearest edge")
  func yClamps() {
    #expect(yCell(value: 50, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: -5, domain: 0...10, plotHeight: 10) == 9)
  }
}
