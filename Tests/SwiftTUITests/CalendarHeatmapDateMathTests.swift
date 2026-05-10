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

  @Test("inferDateRange spans min to max date")
  func inferDateRangeSpansData() {
    let a = Date(timeIntervalSinceReferenceDate: 100)
    let b = Date(timeIntervalSinceReferenceDate: 500)
    let c = Date(timeIntervalSinceReferenceDate: 300)
    let range = inferDateRange([
      DateValue(c, value: 1),
      DateValue(a, value: 2),
      DateValue(b, value: 3),
    ])
    #expect(range?.lowerBound == a)
    #expect(range?.upperBound == b)
  }

  @Test("inferDateRange returns nil for empty input")
  func inferDateRangeNilForEmpty() {
    #expect(inferDateRange([]) == nil)
  }
}
