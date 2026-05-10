import Foundation

/// Returns the minimum-to-maximum date range covered by `days`, or `nil`
/// when the input is empty.
func inferDateRange(_ days: [DateValue]) -> ClosedRange<Date>? {
  guard let first = days.first else { return nil }
  var lower = first.date
  var upper = first.date
  for entry in days.dropFirst() {
    if entry.date < lower { lower = entry.date }
    if entry.date > upper { upper = entry.date }
  }
  return lower...upper
}

/// First day of the week for a `CalendarHeatmap` row layout.
public enum CalendarHeatmapWeekStart: Hashable, Sendable {
  case sunday   // Sun, Mon, ..., Sat (rows 0..6)
  case monday   // Mon, Tue, ..., Sun (rows 0..6)
}

struct CalendarHeatmapBucket: Equatable, Sendable {
  /// `grid[weekdayRow][weekColumn]`. `nil` means "out of range" or "in
  /// range, no data". The view layer distinguishes them by checking
  /// whether the cell's date falls within `range`.
  var grid: [[Double?]]
  /// Column index → month label ("Jan", "Feb", ...) for the first week
  /// of each month; empty string for columns that don't start a month.
  var monthHeader: [String]
  /// Row index → day-of-week label ("", "Mon", "", "Wed", ...). Every
  /// other row is labeled for compactness.
  var dayLabels: [String]
}

/// Bins `days` into a 7-row × N-column intensity grid using `calendar`
/// and `weekStart`. Out-of-range and missing cells stay `nil`; duplicate
/// dates have their values summed.
func bucketDays(
  _ days: [DateValue],
  range: ClosedRange<Date>,
  calendar: Calendar,
  weekStart: CalendarHeatmapWeekStart
) -> CalendarHeatmapBucket {
  let lower = startOfDay(range.lowerBound, in: calendar)
  let upper = startOfDay(range.upperBound, in: calendar)

  // Snap the range start back to the most recent weekStart so column 0
  // is a whole week.
  let firstColumnDate = startOfWeek(lower, weekStart: weekStart, calendar: calendar)

  let columnCount = max(1, weekColumns(from: firstColumnDate, to: upper, calendar: calendar))
  var grid: [[Double?]] = Array(repeating: Array(repeating: nil, count: columnCount), count: 7)

  // Aggregate values per (row, column) cell, summing duplicates.
  for entry in days {
    let day = startOfDay(entry.date, in: calendar)
    guard day >= lower && day <= upper else { continue }
    let (row, col) = position(of: day,
                              from: firstColumnDate,
                              weekStart: weekStart,
                              calendar: calendar)
    guard col >= 0 && col < columnCount else { continue }
    grid[row][col] = (grid[row][col] ?? 0) + entry.value
  }

  let monthHeader = monthHeaderLabels(
    firstColumnDate: firstColumnDate,
    columnCount: columnCount,
    calendar: calendar
  )
  let dayLabels = weekdayLabels(weekStart: weekStart, calendar: calendar)

  return CalendarHeatmapBucket(grid: grid, monthHeader: monthHeader, dayLabels: dayLabels)
}

// MARK: - Internal date arithmetic

private func startOfDay(_ date: Date, in calendar: Calendar) -> Date {
  calendar.startOfDay(for: date)
}

private func startOfWeek(
  _ date: Date,
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> Date {
  let weekdayUnit = calendar.component(.weekday, from: date)  // 1...7, 1 = Sunday
  let offsetFromStart: Int
  switch weekStart {
  case .sunday: offsetFromStart = (weekdayUnit - 1) % 7
  case .monday: offsetFromStart = (weekdayUnit + 5) % 7   // shift so Monday = 0
  }
  return calendar.date(byAdding: .day, value: -offsetFromStart, to: date) ?? date
}

private func weekColumns(
  from start: Date,
  to end: Date,
  calendar: Calendar
) -> Int {
  let days = calendar.dateComponents([.day], from: start, to: end).day ?? 0
  return Int((days / 7)) + 1
}

private func position(
  of day: Date,
  from firstColumnDate: Date,
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> (row: Int, col: Int) {
  let daysSinceStart = calendar.dateComponents([.day], from: firstColumnDate, to: day).day ?? 0
  return (row: daysSinceStart % 7, col: daysSinceStart / 7)
}

private func monthHeaderLabels(
  firstColumnDate: Date,
  columnCount: Int,
  calendar: Calendar
) -> [String] {
  let formatter = DateFormatter()
  formatter.calendar = calendar
  formatter.timeZone = calendar.timeZone
  formatter.dateFormat = "MMM"

  var labels = Array(repeating: "", count: columnCount)
  var lastMonth = -1
  for column in 0..<columnCount {
    guard let date = calendar.date(byAdding: .day, value: column * 7, to: firstColumnDate) else {
      continue
    }
    let month = calendar.component(.month, from: date)
    if month != lastMonth {
      labels[column] = formatter.string(from: date)
      lastMonth = month
    }
  }
  return labels
}

private func weekdayLabels(
  weekStart: CalendarHeatmapWeekStart,
  calendar: Calendar
) -> [String] {
  // Match the screenshot reference: blank, Mon, blank, Wed, blank, Fri, blank
  // (or the Sun-start permutation).
  switch weekStart {
  case .sunday:
    return ["", "Mon", "", "Wed", "", "Fri", ""]
  case .monday:
    return ["", "Tue", "", "Thu", "", "Sat", ""]
  }
}
