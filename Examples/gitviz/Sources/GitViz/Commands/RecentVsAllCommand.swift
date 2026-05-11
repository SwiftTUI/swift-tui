import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct RecentVsAllCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "recent-vs-all",
    abstract: "Top-N authors' last-30-days share vs all-time share."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let commits = try repo.commits(max: opts.maxCommits)
    let entries = BarEntryAdapters.recentVsAllTime(commits, top: opts.top)

    GitVizRunOnce.print(
      ComparisonChart(
        "Authors — last 30 days vs all-time",
        entries: entries,
        barWidth: 18,
        labelWidth: 14
      ),
      opts: opts
    )
  }
}
