import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct VolatilityCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "volatility",
    abstract: "Top-N most-changed files (lifetime change count)."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let files = try repo.fileChangeCounts(max: opts.maxCommits)
    let entries = BarEntryAdapters.volatilityBars(files, top: opts.top)
    GitVizRunOnce.print(
      BarChart(
        "Most-changed files (top \(opts.top))",
        entries: entries,
        barWidth: 16,
        labelWidth: 30
      ),
      opts: opts
    )
  }
}
