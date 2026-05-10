import Foundation
import Testing

@testable import SwiftTUICharts

@Suite("CalendarHeatmap date math")
struct CalendarHeatmapDateMathTests {
  @Test("DateValue stores date and value")
  func dateValueStoresInputs() {
    let date = Date(timeIntervalSinceReferenceDate: 12345)
    let entry = DateValue(date, value: 7.5)
    #expect(entry.date == date)
    #expect(entry.value == 7.5)
  }
}
