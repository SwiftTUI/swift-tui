import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct LocCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "loc",
    abstract: "Net LOC trend over time (cumulative ins − del).",
    discussion: """
      LOC is approximated as cumulative(insertions − deletions). This is a
      proxy that's right for trends and wrong as an absolute. For absolute
      line counts use `cloc` or `tokei`.
      """
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let deltas = try repo.numstat(
      since: opts.sinceDate,
      until: opts.untilDate,
      max: opts.maxCommits
    )
    let series = LineSeriesAdapters.cumulativeLOC(deltas)
    let chart = LineChart(
      "Net LOC (proxy)",
      series: [series],
      height: 8,
      width: opts.resolvedWidth()
    )
    .chartXAxis(.dates(every: .month, format: .dateTime.month(.abbreviated).year(.twoDigits)))
    .chartYAxis(.values(count: 5, format: .number.notation(.compactName)))
    .chartBaseline(.zero)
    .chartLegend(.hidden)

    GitVizRunOnce.print(chart, opts: opts)
  }
}
