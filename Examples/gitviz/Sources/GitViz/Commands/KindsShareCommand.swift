import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct KindsShareCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "kinds-share",
    abstract: "Quarterly share of each commit kind (one stacked bar per quarter)."
  )

  @OptionGroup var opts: GitVizOptions

  @Option(name: .long, help: "Number of trailing quarters to chart.")
  var quarters: Int = 8

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let commits = try repo.commits(
      since: opts.sinceDate,
      until: opts.untilDate,
      max: opts.maxCommits
    )
    let quarters = BarEntryAdapters.quarterlyKindShare(commits, quarters: quarters)

    GitVizRunOnce.print(
      VStack(alignment: .leading, spacing: 0) {
        Text("Commit-kind share per quarter").bold()
        Divider()
        ForEach(quarters, id: \.label) { quarter in
          StackedBarChart(quarter.label, entries: quarter.entries, barWidth: 20)
        }
      },
      opts: opts
    )
  }
}
