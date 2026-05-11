import ArgumentParser
import SwiftTUI
import SwiftTUICharts

struct ConcentrationCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "concentration",
    abstract: "Bus factor / author concentration.",
    discussion: """
      The bus factor is the smallest number of top authors needed to cover
      at least 50% of recent commits. A small bus factor means most of the
      project's recent history sits in a handful of heads.
      """
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let tallies = try repo.shortlog()
    let total = tallies.reduce(0) { $0 + $1.commits }
    let busFactor = computeBusFactor(tallies, total: total)
    let topEntries = tallies.prefix(opts.top).map { tally in
      BarChartEntry(tally.name, value: Double(tally.commits), tone: AuthorPaletteAdapter.tone(for: tally.name))
    }

    GitVizRunOnce.print(
      VStack(alignment: .leading, spacing: 0) {
        Text("Author concentration").bold()
        Divider()
        Meter(
          "Bus factor",
          value: Double(busFactor),
          total: Double(max(tallies.count, 1)),
          tone: .warning
        )
        Divider()
        StackedBarChart("Commit share — top \(opts.top)", entries: topEntries, total: Double(total), barWidth: 28)
      },
      opts: opts
    )
  }

  private func computeBusFactor(_ tallies: [AuthorTally], total: Int) -> Int {
    guard total > 0 else { return 0 }
    let target = (total + 1) / 2  // smallest k with sum(top-k) >= 50%
    var running = 0
    for (offset, tally) in tallies.enumerated() {
      running += tally.commits
      if running >= target { return offset + 1 }
    }
    return tallies.count
  }
}
