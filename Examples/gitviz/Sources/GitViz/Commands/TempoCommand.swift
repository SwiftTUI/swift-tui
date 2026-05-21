import ArgumentParser
import Foundation
import SwiftTUI
import SwiftTUICharts

struct TempoCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "tempo",
    abstract: "Weekly commit sparkline per top-N author."
  )

  @OptionGroup var opts: GitVizOptions

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let calendar = Calendar.current
    let now = Date()
    let start =
      opts.sinceDate
      ?? calendar.date(byAdding: .month, value: -6, to: now)
      ?? now
    let end = opts.untilDate ?? now

    let commits = try repo.commits(
      since: start,
      until: end,
      max: opts.maxCommits
    )
    let perAuthor = DateValueAdapters.weeklyCommitsPerAuthor(
      commits: commits,
      topN: opts.top,
      in: start...end,
      calendar: calendar
    )
    let toned = AuthorPaletteAdapter.assign(perAuthor)

    GitVizRunOnce.print(
      VStack(alignment: .leading, spacing: 0) {
        Text("Weekly commits per author").bold()
        Divider()
        ForEach(toned, id: \.author) { entry in
          Sparkline(entry.author, values: entry.values, tone: entry.tone)
        }
      },
      opts: opts
    )
  }
}
