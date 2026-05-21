import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct HealthCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "health",
    abstract: "Percentage of touched lines authored in the last year.",
    discussion: """
      Approximates "is most of our code fresh?" as the share of commits in
      the last year by total touched lines. This is a directional signal,
      not an authoritative blame analysis.
      """
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let deltas = try repo.numstat(max: opts.maxCommits)
    let now = Date()
    let oneYearAgo = Calendar.current.date(byAdding: .year, value: -1, to: now) ?? now

    let totalTouched = deltas.reduce(0) { $0 + $1.insertions + $1.deletions }
    let recentTouched =
      deltas
      .filter { $0.date >= oneYearAgo }
      .reduce(0) { $0 + $1.insertions + $1.deletions }
    let share = totalTouched == 0 ? 0.0 : Double(recentTouched) / Double(totalTouched)

    let bands: [ThresholdBand] = [
      ThresholdBand(upTo: 0.3, tone: .critical),
      ThresholdBand(upTo: 0.6, tone: .warning),
      ThresholdBand(upTo: 0.8, tone: .info),
      ThresholdBand(upTo: 1.0, tone: .success),
    ]
    GitVizRunOnce.print(
      ThresholdGauge(
        "Recent code share (last 12 months)",
        value: share,
        total: 1,
        bands: bands,
        barWidth: 24
      ),
      opts: opts
    )
  }
}
