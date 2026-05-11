import Foundation

/// Repository-level summary used by `gitviz info`.
struct RepoInfo: Sendable, Hashable {
  var path: URL
  var branch: String?
  var commitCount: Int
  var contributorCount: Int
  var firstCommitDate: Date?
  var lastCommitDate: Date?
  var tagCount: Int
  /// `scanned / total` when `--max-commits` truncates the scan.
  var scannedCommitShare: Double
}

/// One git commit's metadata plus optional numstat tallies.
struct Commit: Sendable, Hashable {
  var sha: String
  var date: Date
  var authorName: String
  var authorEmail: String
  var subject: String
  var parents: [String]
  var insertions: Int
  var deletions: Int
}

/// A commit's numstat tally (file count + line-level changes), independent of
/// commit metadata. Used by `loc` and `deltas`.
struct CommitDelta: Sendable, Hashable {
  var sha: String
  var date: Date
  var insertions: Int
  var deletions: Int
  var filesChanged: Int
}

/// One author's commit count produced by `git shortlog -s -n -e`.
struct AuthorTally: Sendable, Hashable {
  var name: String
  var email: String
  var commits: Int
}

/// A single file's lifetime change count.
struct FileTally: Sendable, Hashable {
  var path: String
  var changeCount: Int
}

/// A git tag. `isAnnotated` distinguishes `git tag -a` from lightweight tags.
struct Tag: Sendable, Hashable {
  var name: String
  var sha: String
  var date: Date
  var isAnnotated: Bool
}

/// One cell of a DAG row, paired with the lane it belongs to. Lane
/// indices are used by the renderer to look up per-lane colors so eyes
/// can trace a single branch through a multi-lane view. Inter-lane
/// separator columns (blank spaces between lane positions) get `lane =
/// nil` and render uncolored.
struct GraphGlyph: Sendable, Hashable {
  var character: Character
  var lane: Int?
}

/// A commit prepared for DAG rendering — pre-laid-out into lanes and a
/// per-row glyph stream by `GraphLayout`.
///
/// `connectorGlyphs`, when non-nil, is a glyph-only row to emit
/// immediately below this commit's line. Used to draw merge fan-out
/// (`├─╮`) and branch convergence (`├─╯`) connectors so the resulting
/// DAG view actually shows joined lines at merges and joins.
struct GraphCommit: Sendable, Hashable {
  var sha: String
  var parents: [String]
  var subject: String
  var lane: Int
  var glyphs: [GraphGlyph]
  var connectorGlyphs: [GraphGlyph]?

  /// Plain-text view of the commit row (no color information). Used by
  /// tests asserting glyph layout.
  var glyphRow: String { String(glyphs.map(\.character)) }

  /// Plain-text view of the connector row below this commit, or nil if
  /// there's no connector.
  var connectorBelow: String? {
    connectorGlyphs.map { String($0.map(\.character)) }
  }
}
