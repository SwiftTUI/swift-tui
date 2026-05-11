import Foundation
import SwiftTUICharts

/// Adapters that produce `LineChartSeries` from commit history.
enum LineSeriesAdapters {
  /// Two parallel series — insertions and deletions — bucketed per calendar
  /// day, sorted ascending by date. Use with `LineChart(.., series:[ins,del], height: 8)`.
  static func dailyDeltas(
    _ deltas: [CommitDelta],
    calendar: Calendar = .current
  ) -> (insertions: LineChartSeries, deletions: LineChartSeries) {
    var insertionsByDay: [Date: Double] = [:]
    var deletionsByDay: [Date: Double] = [:]
    for delta in deltas {
      let day = calendar.startOfDay(for: delta.date)
      insertionsByDay[day, default: 0] += Double(delta.insertions)
      deletionsByDay[day, default: 0] += Double(delta.deletions)
    }
    let allDays = Set(insertionsByDay.keys).union(deletionsByDay.keys).sorted()
    let insertions = LineChartSeries(
      "Insertions",
      points: allDays.map { LineChartPoint(date: $0, value: insertionsByDay[$0] ?? 0) },
      style: .line,
      tone: .success
    )
    let deletions = LineChartSeries(
      "Deletions",
      points: allDays.map { LineChartPoint(date: $0, value: deletionsByDay[$0] ?? 0) },
      style: .line,
      tone: .critical
    )
    return (insertions, deletions)
  }

  /// Single cumulative-LOC area series (running `cumulative(ins − del)`),
  /// sorted ascending by date. This is a proxy for net LOC; documented as
  /// such in the `gitviz loc` help text.
  static func cumulativeLOC(
    _ deltas: [CommitDelta],
    calendar: Calendar = .current
  ) -> LineChartSeries {
    var perDay: [Date: Double] = [:]
    for delta in deltas {
      let day = calendar.startOfDay(for: delta.date)
      perDay[day, default: 0] += Double(delta.insertions - delta.deletions)
    }
    let sortedDays = perDay.keys.sorted()
    var running: Double = 0
    let points = sortedDays.map { day -> LineChartPoint in
      running += perDay[day] ?? 0
      return LineChartPoint(date: day, value: running)
    }
    return LineChartSeries("Net LOC", points: points, style: .area, tone: .info)
  }
}
