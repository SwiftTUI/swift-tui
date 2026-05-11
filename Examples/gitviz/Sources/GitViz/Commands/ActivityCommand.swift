import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct ActivityCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "activity",
    abstract: "GitHub-style daily commit calendar (last 12 months by default)."
  )

  @OptionGroup var opts: GitVizOptions

  @Option(name: .long, help: "Restrict the calendar to a single calendar year.")
  var year: Int?

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let calendar = Calendar.current
    let (start, end) = window(in: calendar)
    let commits = try repo.commits(
      since: start,
      until: end,
      max: opts.maxCommits
    )
    let days = DateValueAdapters.dailyCommitCounts(
      commits: commits,
      in: start...end,
      calendar: calendar
    )

    let title = year.map { "Commits in \($0)" } ?? "Commits — last 12 months"

    GitVizRunOnce.print(
      CalendarHeatmap(
        title,
        days: days,
        range: start...end,
        weekStart: .monday,
        showsMonthHeader: true,
        showsDayLabels: true,
        showsScaleLegend: true,
        tone: .info
      ),
      opts: opts
    )
  }

  private func window(in calendar: Calendar) -> (Date, Date) {
    let now = Date()
    if let year {
      var startComponents = DateComponents()
      startComponents.year = year
      startComponents.month = 1
      startComponents.day = 1
      let start = calendar.date(from: startComponents) ?? now
      var endComponents = DateComponents()
      endComponents.year = year
      endComponents.month = 12
      endComponents.day = 31
      let end = calendar.date(from: endComponents) ?? now
      return (start, end)
    }
    let start = calendar.date(byAdding: .month, value: -12, to: now) ?? now
    return (start, now)
  }
}
