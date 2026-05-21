import Foundation
import SwiftTUICharts

/// Adapters that produce `BarChartEntry` / `ComparisonEntry` / `LegendItem`
/// arrays from git data.
enum BarEntryAdapters {
  /// File-change-frequency bars, top `n`. Paths are truncated to `pathLimit`
  /// from the front (keeping the filename tail) for readability.
  static func volatilityBars(
    _ files: [FileTally],
    top n: Int,
    pathLimit: Int = 28
  ) -> [BarChartEntry] {
    files.prefix(n).map { tally in
      BarChartEntry(
        truncatePath(tally.path, limit: pathLimit),
        value: Double(tally.changeCount),
        tone: .info
      )
    }
  }

  /// Per-kind counts (feat / fix / refactor / …) preserved in the
  /// `CommitKind.allCases` order so users see a stable column ordering
  /// across runs.
  static func commitKindCounts(_ commits: [Commit]) -> [BarChartEntry] {
    var counts: [CommitKind: Int] = [:]
    for commit in commits {
      counts[CommitKind.classify(commit.subject), default: 0] += 1
    }
    return CommitKind.allCases
      .compactMap { kind -> BarChartEntry? in
        guard let count = counts[kind], count > 0 else { return nil }
        return BarChartEntry(kind.rawValue, value: Double(count), tone: tone(for: kind))
      }
  }

  /// Per-author 30-day-vs-all-time share, top `n`. Useful for the
  /// `ComparisonChart` motivating case.
  static func recentVsAllTime(
    _ commits: [Commit],
    top n: Int,
    recentWindow: TimeInterval = 30 * 24 * 60 * 60,
    now: Date = Date()
  ) -> [ComparisonEntry] {
    let recentStart = now.addingTimeInterval(-recentWindow)
    var allTime: [String: Int] = [:]
    var recent: [String: Int] = [:]
    for commit in commits {
      let key = commit.authorName.isEmpty ? commit.authorEmail : commit.authorName
      allTime[key, default: 0] += 1
      if commit.date >= recentStart {
        recent[key, default: 0] += 1
      }
    }
    let topAuthors =
      allTime
      .sorted { lhs, rhs in lhs.value > rhs.value }
      .prefix(n)
      .map(\.key)

    return topAuthors.map { author in
      ComparisonEntry(
        author,
        current: Double(recent[author] ?? 0),
        baseline: Double(allTime[author] ?? 0)
      )
    }
  }

  /// Last 8 quarters × per-kind stacked-bar entries. Returns one
  /// `QuarterShare` per quarter so the command can render one
  /// `StackedBarChart` per quarter.
  static func quarterlyKindShare(
    _ commits: [Commit],
    quarters: Int = 8,
    now: Date = Date(),
    calendar: Calendar = .current
  ) -> [QuarterShare] {
    var quarterStarts: [Date] = []
    var cursor = startOfQuarter(now, calendar: calendar)
    for _ in 0..<quarters {
      quarterStarts.append(cursor)
      guard let next = calendar.date(byAdding: .month, value: -3, to: cursor) else { break }
      cursor = next
    }
    quarterStarts.reverse()  // oldest first.

    return quarterStarts.enumerated().map { (offset, start) in
      let end: Date
      if offset == quarterStarts.count - 1 {
        end = calendar.date(byAdding: .month, value: 3, to: start) ?? now
      } else {
        end = quarterStarts[offset + 1]
      }
      let slice = commits.filter { $0.date >= start && $0.date < end }
      let entries = commitKindCounts(slice)
      let label = quarterLabel(for: start, calendar: calendar)
      return QuarterShare(label: label, entries: entries)
    }
  }

  // MARK: - Helpers

  private static func tone(for kind: CommitKind) -> BannerTone {
    switch kind {
    case .feat: return .success
    case .fix, .hotfix: return .critical
    case .perf: return .info
    case .ci, .chore, .docs, .test, .refactor, .revert, .other: return .automatic
    }
  }

  private static func truncatePath(_ path: String, limit: Int) -> String {
    if path.count <= limit { return path }
    let suffix = path.suffix(limit - 1)
    return "…" + suffix
  }

  private static func startOfQuarter(_ date: Date, calendar: Calendar) -> Date {
    let components = calendar.dateComponents([.year, .month], from: date)
    let month = ((components.month ?? 1) - 1) / 3 * 3 + 1
    var rebuilt = DateComponents()
    rebuilt.year = components.year
    rebuilt.month = month
    rebuilt.day = 1
    return calendar.date(from: rebuilt) ?? date
  }

}

/// One quarter's commit-kind tallies. Pulled out as a struct (rather than a
/// tuple) so SwiftUI's `ForEach(_:id:)` can key off `label`.
struct QuarterShare: Hashable, Sendable {
  let label: String
  let entries: [BarChartEntry]
}

extension BarEntryAdapters {
  private static func quarterLabel(for start: Date, calendar: Calendar) -> String {
    let components = calendar.dateComponents([.year, .month], from: start)
    guard let year = components.year, let month = components.month else { return "?" }
    let quarter = (month - 1) / 3 + 1
    return "Q\(quarter) '\(year % 100)"
  }
}
