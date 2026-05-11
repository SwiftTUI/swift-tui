import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct PulseCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "pulse",
    abstract: "Current week's commits vs trailing 4-week median target."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let calendar = Calendar.current
    let now = Date()
    let fiveWeeksAgo =
      calendar.date(byAdding: .weekOfYear, value: -5, to: now) ?? now
    let commits = try repo.commits(since: fiveWeeksAgo, max: opts.maxCommits)
    let perWeek = weeklyTotals(commits, in: fiveWeeksAgo...now, calendar: calendar)
    let current = Double(perWeek.last ?? 0)
    let trailing = Array(perWeek.dropLast())
    let target = median(trailing)
    let total = max(current, target, 1) * 1.5

    GitVizRunOnce.print(
      BulletChart(
        "Commits this week vs trailing median",
        value: current,
        target: target,
        total: total,
        tone: .info
      ),
      opts: opts
    )
  }

  private func weeklyTotals(
    _ commits: [Commit],
    in range: ClosedRange<Date>,
    calendar: Calendar
  ) -> [Int] {
    var starts: [Date] = []
    var cursor = startOfWeek(range.lowerBound, calendar: calendar)
    let end = startOfWeek(range.upperBound, calendar: calendar)
    while cursor <= end {
      starts.append(cursor)
      guard let next = calendar.date(byAdding: .weekOfYear, value: 1, to: cursor) else { break }
      cursor = next
    }
    var totals = Array(repeating: 0, count: starts.count)
    let index: [Date: Int] = Dictionary(uniqueKeysWithValues: starts.enumerated().map { ($1, $0) })
    for commit in commits {
      let week = startOfWeek(commit.date, calendar: calendar)
      if let i = index[week] {
        totals[i] += 1
      }
    }
    return totals
  }

  private func startOfWeek(_ date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
    return calendar.date(from: components) ?? calendar.startOfDay(for: date)
  }

  private func median(_ values: [Int]) -> Double {
    guard !values.isEmpty else { return 0 }
    let sorted = values.sorted()
    if sorted.count.isMultiple(of: 2) {
      let mid = sorted.count / 2
      return Double(sorted[mid - 1] + sorted[mid]) / 2.0
    }
    return Double(sorted[sorted.count / 2])
  }
}
