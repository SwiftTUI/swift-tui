import Foundation
import Testing

@testable import GitViz

struct AdaptersTests {
  private let calendar: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "UTC")!
    return calendar
  }()

  @Test("dailyCommitCounts fills zeros for empty days in the range")
  func dailyCommitCountsFillsZeros() {
    let day1 = isoDate("2026-04-01T00:00:00Z")
    let day3 = isoDate("2026-04-03T00:00:00Z")
    let commits = [
      sampleCommit(at: day1, subject: "feat: a"),
      sampleCommit(at: day1, subject: "feat: b"),
      sampleCommit(at: day3, subject: "fix: c"),
    ]
    let series = DateValueAdapters.dailyCommitCounts(
      commits: commits,
      in: day1...day3,
      calendar: calendar
    )
    #expect(series.count == 3)
    #expect(series[0].value == 2)
    #expect(series[1].value == 0)
    #expect(series[2].value == 1)
  }

  @Test("hourlyCommitCounts produces exactly 24 entries")
  func hourlyAlwaysReturns24() {
    let series = DateValueAdapters.hourlyCommitCounts(commits: [])
    #expect(series.count == 24)
    #expect(series.allSatisfy { $0.value == 0 })
  }

  @Test("dailyDeltas separates inserted/deleted counts by date")
  func dailyDeltasSplits() {
    let day = isoDate("2026-04-01T00:00:00Z")
    let deltas = [
      CommitDelta(sha: "a", date: day, insertions: 10, deletions: 2, filesChanged: 1),
      CommitDelta(sha: "b", date: day, insertions: 5, deletions: 0, filesChanged: 1),
    ]
    let (insertions, deletions) = LineSeriesAdapters.dailyDeltas(deltas, calendar: calendar)
    #expect(insertions.label == "Insertions")
    #expect(deletions.label == "Deletions")
    #expect(insertions.points.first?.y == 15)
    #expect(deletions.points.first?.y == 2)
  }

  @Test("cumulativeLOC produces a running sum")
  func cumulativeLOCRuns() {
    let day1 = isoDate("2026-04-01T00:00:00Z")
    let day2 = isoDate("2026-04-02T00:00:00Z")
    let deltas = [
      CommitDelta(sha: "a", date: day1, insertions: 10, deletions: 5, filesChanged: 1),
      CommitDelta(sha: "b", date: day2, insertions: 4, deletions: 1, filesChanged: 1),
    ]
    let series = LineSeriesAdapters.cumulativeLOC(deltas, calendar: calendar)
    #expect(series.points.count == 2)
    #expect(series.points[0].y == 5)  // 10 - 5
    #expect(series.points[1].y == 8)  // running 5 + (4 - 1)
  }

  @Test("commitKindCounts uses CommitKind.allCases ordering")
  func commitKindCountsOrdered() {
    let commits = [
      sampleCommit(at: Date(), subject: "feat: x"),
      sampleCommit(at: Date(), subject: "feat: y"),
      sampleCommit(at: Date(), subject: "fix: z"),
    ]
    let entries = BarEntryAdapters.commitKindCounts(commits)
    #expect(entries.first?.label == "feat")
    #expect(entries.first?.value == 2)
  }

  @Test("volatilityBars truncates long paths from the front")
  func volatilityTruncatesPaths() {
    let tally = FileTally(path: String(repeating: "a/", count: 30) + "leaf.swift", changeCount: 10)
    let bars = BarEntryAdapters.volatilityBars([tally], top: 1, pathLimit: 12)
    #expect(bars.first?.label.hasPrefix("…") == true)
    #expect(bars.first?.label.hasSuffix("leaf.swift") == true)
  }

  @Test("AuthorPaletteAdapter returns a stable tone for the same key")
  func authorPaletteIsStable() {
    let a = AuthorPaletteAdapter.tone(for: "Alice")
    let b = AuthorPaletteAdapter.tone(for: "Alice")
    let c = AuthorPaletteAdapter.tone(for: "alice")
    #expect(a == b)
    #expect(a == c)  // case-insensitive
  }

  // MARK: - Helpers

  private func isoDate(_ raw: String) -> Date {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withInternetDateTime]
    return formatter.date(from: raw) ?? Date()
  }

  private func sampleCommit(at date: Date, subject: String) -> Commit {
    Commit(
      sha: UUID().uuidString,
      date: date,
      authorName: "Author",
      authorEmail: "author@example.com",
      subject: subject,
      parents: [],
      insertions: 0,
      deletions: 0
    )
  }
}
