import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct CadenceCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "cadence",
    abstract: "Commit activity by hour-of-day (24-cell heat strip)."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let commits = try repo.commits(
      since: opts.sinceDate,
      until: opts.untilDate,
      max: opts.maxCommits
    )
    let entries = DateValueAdapters.hourlyCommitCounts(commits: commits)
    GitVizRunOnce.print(
      HeatStrip("Commits by hour-of-day", entries: entries, cellWidth: 2),
      opts: opts
    )
  }
}
