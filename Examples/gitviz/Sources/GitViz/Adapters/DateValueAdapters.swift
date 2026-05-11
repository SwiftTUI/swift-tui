import Foundation
import SwiftTUICharts

/// Pure functions turning git commit history into `[DateValue]` series for
/// date-axis charts (`CalendarHeatmap`, date-axis `LineChart`, etc.).
enum DateValueAdapters {
  /// Counts commits per calendar day in `range`, producing one
  /// `DateValue` per day (filling in zeros for empty days).
  static func dailyCommitCounts(
    commits: [Commit],
    in range: ClosedRange<Date>,
    calendar: Calendar = .current
  ) -> [DateValue] {
    var perDay: [Date: Int] = [:]
    for commit in commits {
      let day = calendar.startOfDay(for: commit.date)
      guard range.contains(day) else { continue }
      perDay[day, default: 0] += 1
    }

    var output: [DateValue] = []
    var cursor = calendar.startOfDay(for: range.lowerBound)
    let end = calendar.startOfDay(for: range.upperBound)
    while cursor <= end {
      output.append(DateValue(cursor, value: Double(perDay[cursor] ?? 0)))
      guard let next = calendar.date(byAdding: .day, value: 1, to: cursor) else { break }
      cursor = next
    }
    return output
  }

  /// Counts commits per hour-of-day (0..23). Returns 24 `DateValue`s
  /// anchored to an arbitrary reference date — the `date` field is a
  /// placeholder, the index encodes the hour.
  static func hourlyCommitCounts(
    commits: [Commit],
    calendar: Calendar = .current
  ) -> [BarChartEntry] {
    var perHour = Array(repeating: 0, count: 24)
    for commit in commits {
      let hour = calendar.component(.hour, from: commit.date)
      if hour >= 0, hour < 24 {
        perHour[hour] += 1
      }
    }
    return perHour.enumerated().map { (index, count) in
      BarChartEntry(String(index), value: Double(count))
    }
  }

  /// Splits commits into a per-author weekly histogram and returns the
  /// top `topN` authors' time series, sorted desc by total commits.
  ///
  /// Returns `(author, weeklyCounts)` pairs where `weeklyCounts.count`
  /// equals the number of weeks spanned by `range`.
  static func weeklyCommitsPerAuthor(
    commits: [Commit],
    topN: Int,
    in range: ClosedRange<Date>,
    calendar: Calendar = .current
  ) -> [(author: String, values: [Double])] {
    // Establish week boundaries.
    var weekStarts: [Date] = []
    var cursor = startOfWeek(range.lowerBound, calendar: calendar)
    let endWeek = startOfWeek(range.upperBound, calendar: calendar)
    while cursor <= endWeek {
      weekStarts.append(cursor)
      guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
      cursor = next
    }
    let weekIndex: [Date: Int] = Dictionary(
      uniqueKeysWithValues: weekStarts.enumerated().map { ($1, $0) }
    )

    var perAuthor: [String: [Double]] = [:]
    var totals: [String: Int] = [:]
    for commit in commits {
      let key = commit.authorName.isEmpty ? commit.authorEmail : commit.authorName
      let week = startOfWeek(commit.date, calendar: calendar)
      guard let index = weekIndex[week] else { continue }
      if perAuthor[key] == nil {
        perAuthor[key] = Array(repeating: 0, count: weekStarts.count)
      }
      perAuthor[key]?[index] += 1
      totals[key, default: 0] += 1
    }

    let top = totals
      .sorted { lhs, rhs in lhs.value > rhs.value }
      .prefix(topN)
      .map(\.key)

    return top.map { author in
      (author: author, values: perAuthor[author] ?? [])
    }
  }

  private static func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components) ?? calendar.startOfDay(for: date)
  }
}
