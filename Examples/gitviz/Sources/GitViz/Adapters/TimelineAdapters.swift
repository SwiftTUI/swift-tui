import Foundation
import SwiftTUICharts

/// Adapters that produce `TimelineEntry` arrays from git data.
enum TimelineAdapters {
  /// Milestone timeline used by `gitviz info`. Combines first-commit, head,
  /// and the most recent annotated tag (when present).
  static func infoMilestones(
    info: RepoInfo,
    tags: [Tag],
    calendar: Calendar = .current
  ) -> [TimelineEntry] {
    var entries: [TimelineEntry] = []
    if let firstCommit = info.firstCommitDate {
      entries.append(
        TimelineEntry("First commit", detail: shortDate(firstCommit, calendar: calendar))
      )
    }
    if let mostRecentAnnotated = tags.filter(\.isAnnotated).max(by: { $0.date < $1.date }) {
      entries.append(
        TimelineEntry(
          "Tag \(mostRecentAnnotated.name)",
          detail: shortDate(mostRecentAnnotated.date, calendar: calendar),
          tone: .info
        )
      )
    }
    if let lastCommit = info.lastCommitDate {
      entries.append(
        TimelineEntry(
          "HEAD",
          detail: shortDate(lastCommit, calendar: calendar),
          tone: .success
        )
      )
    }
    return entries
  }

  /// Release-history timeline used by `gitviz releases`. Annotated tags get
  /// a different tone than lightweight ones.
  static func releaseHistory(
    _ tags: [Tag],
    maxEntries: Int,
    calendar: Calendar = .current
  ) -> [TimelineEntry] {
    tags
      .sorted { lhs, rhs in lhs.date > rhs.date }
      .prefix(maxEntries)
      .map { tag in
        TimelineEntry(
          tag.name,
          detail: shortDate(tag.date, calendar: calendar),
          tone: tag.isAnnotated ? .success : .automatic
        )
      }
  }

  // MARK: - Helpers

  private static func shortDate(_ date: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month, .day], from: date)
    guard
      let year = components.year, let month = components.month, let day = components.day
    else { return "?" }
    return String(format: "%04d-%02d-%02d", year, month, day)
  }
}
