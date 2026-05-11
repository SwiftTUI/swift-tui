import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct KindsCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kinds",
    abstract: "Commit-kind counts (feat / fix / refactor / …)."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let commits = try repo.commits(
      since: opts.sinceDate,
      until: opts.untilDate,
      max: opts.maxCommits
    )
    let entries = BarEntryAdapters.commitKindCounts(commits)
    GitVizRunOnce.print(
      ColumnChart(
        "Commit kinds",
        entries: entries,
        chartHeight: 6,
        columnWidth: 4
      ),
      opts: opts
    )
  }
}
