import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct ReleasesCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "releases",
    abstract: "Tag and release history."
  )

  @OptionGroup var opts: GitVizOptions

  @Option(name: .long, help: "Maximum number of tags to show (newest first).")
  var max: Int = 20

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let tags = try repo.tags()
    let entries = TimelineAdapters.releaseHistory(tags, maxEntries: max)
    GitVizRunOnce.print(
      ChartCard(title: "Releases (newest first)") {
        Timeline(entries)
      },
      opts: opts
    )
  }
}
