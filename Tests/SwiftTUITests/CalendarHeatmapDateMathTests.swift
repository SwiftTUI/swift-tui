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

  private static func makeUTCGregorian() -> Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }

  private static func date(_ string: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    formatter.timeZone = TimeZone(identifier: "UTC")
    return formatter.date(from: string)!
  }

  @Test("bucketDays lays out a single week with Sunday start")
  func bucketDaysSingleWeekSundayStart() {
    let cal = Self.makeUTCGregorian()
    // 2024-01-07 is a Sunday in the gregorian calendar.
    let days = [
      DateValue(Self.date("2024-01-07"), value: 1),  // Sun
      DateValue(Self.date("2024-01-08"), value: 2),  // Mon
      DateValue(Self.date("2024-01-10"), value: 3),  // Wed
      DateValue(Self.date("2024-01-13"), value: 4),  // Sat
    ]
    let bucket = bucketDays(
      days,
      range: Self.date("2024-01-07")...Self.date("2024-01-13"),
      calendar: cal,
      weekStart: .sunday
    )
    #expect(bucket.grid.count == 7)             // 7 weekday rows
    #expect(bucket.grid[0].count == 1)          // 1 week column
    #expect(bucket.grid[0][0] == 1)             // Sun row, week 0
    #expect(bucket.grid[1][0] == 2)             // Mon row
    #expect(bucket.grid[3][0] == 3)             // Wed row
    #expect(bucket.grid[6][0] == 4)             // Sat row
    #expect(bucket.grid[2][0] == nil)           // Tue, no data
  }

  @Test("bucketDays with Monday start shifts row order")
  func bucketDaysMondayStart() {
    let cal = Self.makeUTCGregorian()
    let days = [
      DateValue(Self.date("2024-01-08"), value: 1),  // Mon
      DateValue(Self.date("2024-01-14"), value: 2),  // Sun
    ]
    let bucket = bucketDays(
      days,
      range: Self.date("2024-01-08")...Self.date("2024-01-14"),
      calendar: cal,
      weekStart: .monday
    )
    #expect(bucket.grid[0][0] == 1)   // Monday is row 0 now
    #expect(bucket.grid[6][0] == 2)   // Sunday is row 6 now
  }

  @Test("bucketDays sums duplicate dates")
  func bucketDaysSumsDuplicates() {
    let cal = Self.makeUTCGregorian()
    let day = Self.date("2024-01-07")
    let days = [
      DateValue(day, value: 3),
      DateValue(day, value: 5),
    ]
    let bucket = bucketDays(
      days,
      range: day...day,
      calendar: cal,
      weekStart: .sunday
    )
    #expect(bucket.grid[0][0] == 8)
  }

  @Test("bucketDays spans multiple weeks with correct column assignment")
  func bucketDaysMultipleWeeks() {
    let cal = Self.makeUTCGregorian()
    // 2024-01-07 (Sun) → 2024-01-27 (Sat) = 3 full weeks.
    let days = [
      DateValue(Self.date("2024-01-07"), value: 1),   // Sun, week 0
      DateValue(Self.date("2024-01-13"), value: 2),   // Sat, week 0
      DateValue(Self.date("2024-01-14"), value: 3),   // Sun, week 1
      DateValue(Self.date("2024-01-21"), value: 4),   // Sun, week 2
      DateValue(Self.date("2024-01-27"), value: 5),   // Sat, week 2
    ]
    let bucket = bucketDays(
      days,
      range: Self.date("2024-01-07")...Self.date("2024-01-27"),
      calendar: cal,
      weekStart: .sunday
    )
    #expect(bucket.grid.count == 7)
    #expect(bucket.grid[0].count == 3)         // 3 week columns
    #expect(bucket.grid[0][0] == 1)            // Sun, week 0
    #expect(bucket.grid[6][0] == 2)            // Sat, week 0
    #expect(bucket.grid[0][1] == 3)            // Sun, week 1
    #expect(bucket.grid[0][2] == 4)            // Sun, week 2
    #expect(bucket.grid[6][2] == 5)            // Sat, week 2
    #expect(bucket.grid[0][2] != nil)
    #expect(bucket.grid[1][0] == nil)          // Mon week 0, no data
  }
}
