import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct InfoCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "info",
    abstract: "Show repository metadata, milestones, and scan progress."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let info = try repo.info(maxCommitsForScannedShare: opts.maxCommits)
    let tags = (try? repo.tags()) ?? []
    let milestones = TimelineAdapters.infoMilestones(info: info, tags: tags)

    let scanned = clamp(info.scannedCommitShare, to: 0...1)

    GitVizRunOnce.print(
      ChartCard(
        title: "Repository",
        subtitle: info.branch.map { "branch \($0)" } ?? nil
      ) {
        VStack(alignment: .leading, spacing: 0) {
          LabeledContent("Path", value: opts.resolvedPath.path)
          LabeledContent("Commits", value: String(info.commitCount))
          LabeledContent("Contributors", value: String(info.contributorCount))
          LabeledContent("Tags", value: String(info.tagCount))
          if scanned < 1 {
            Divider()
            Text("Scan window (\(opts.maxCommits) commits)").bold()
            Meter(
              "Scanned",
              value: Double(min(opts.maxCommits, info.commitCount)),
              total: Double(max(info.commitCount, 1)),
              tone: .info
            )
          }
          if !milestones.isEmpty {
            Divider()
            Text("Milestones").bold()
            Timeline(milestones)
          }
        }
      },
      opts: opts
    )
  }

  private func clamp(_ value: Double, to range: ClosedRange<Double>) -> Double {
    min(max(value, range.lowerBound), range.upperBound)
  }
}
