import Foundation

/// Errors specific to working with a `GitRepo` (separate from `GitProcessError`
/// which is concerned only with process-level failures).
enum GitRepoError: Error, CustomStringConvertible, Sendable {
  case notARepository(path: URL)

  var description: String {
    switch self {
    case .notARepository(let path):
      return "\(path.path) is not a git repository (no .git directory)."
    }
  }
}

/// Public facade over the local git binary. Synchronous, throwing,
/// `Sendable`.
struct GitRepo: Sendable {
  let workingDirectory: URL

  init(workingDirectory: URL) throws {
    var isDirectory: ObjCBool = false
    let dotGit = workingDirectory.appendingPathComponent(".git").path
    guard FileManager.default.fileExists(atPath: dotGit, isDirectory: &isDirectory) else {
      throw GitRepoError.notARepository(path: workingDirectory)
    }
    self.workingDirectory = workingDirectory
  }

  // MARK: - High-level summaries

  /// Repository-level summary used by `gitviz info`.
  func info(maxCommitsForScannedShare maxScan: Int? = nil) throws -> RepoInfo {
    let branch = try? run(["rev-parse", "--abbrev-ref", "HEAD"]).trimmedLine
    let commitCount =
      (try? GitParsers.parseInteger(run(["rev-list", "--count", "HEAD"]))) ?? 0
    let firstCommit = (try? run([
      "log", "--reverse", "--pretty=format:%aI", "--max-count", "1",
    ]).trimmedLine).flatMap { GitParsers.parseISODate($0) }
    let lastCommit = (try? run([
      "log", "--pretty=format:%aI", "--max-count", "1",
    ]).trimmedLine).flatMap { GitParsers.parseISODate($0) }
    let contributorCount =
      (try? run(["shortlog", "-s", "-n", "-e", "HEAD"]).lineCount) ?? 0
    let tagCount =
      (try? run(["tag", "--list"]).lineCount) ?? 0

    let scanned: Int
    if let maxScan, maxScan > 0, commitCount > 0 {
      scanned = min(maxScan, commitCount)
    } else {
      scanned = commitCount
    }
    let share: Double
    if commitCount > 0 {
      share = Double(scanned) / Double(commitCount)
    } else {
      share = 1.0
    }

    return RepoInfo(
      path: workingDirectory,
      branch: branch?.isEmpty == true ? nil : branch,
      commitCount: commitCount,
      contributorCount: contributorCount,
      firstCommitDate: firstCommit,
      lastCommitDate: lastCommit,
      tagCount: tagCount,
      scannedCommitShare: share
    )
  }

  // MARK: - Commit lists

  /// Returns the commit history, newest first, optionally bounded.
  func commits(
    since: Date? = nil,
    until: Date? = nil,
    max: Int? = nil
  ) throws -> [Commit] {
    var args: [String] = [
      "log",
      "--no-color",
      "-z",
      "--pretty=format:\(GitParsers.recordSeparator)\(GitParsers.logFormat)",
      "--numstat",
    ]
    if let since {
      args.append("--since=\(formatGitDate(since))")
    }
    if let until {
      args.append("--until=\(formatGitDate(until))")
    }
    if let max {
      args.append("--max-count=\(max)")
    }
    let raw = try run(args)
    return GitParsers.parseLogWithNumstat(raw)
  }

  /// Per-commit deltas (numstat tallies) since/until/max-bounded.
  func numstat(
    since: Date? = nil,
    until: Date? = nil,
    max: Int? = nil
  ) throws -> [CommitDelta] {
    let commits = try commits(since: since, until: until, max: max)
    return GitParsers.deltas(from: commits)
  }

  /// `git shortlog -s -n -e` parsed into author tallies, sorted desc by count.
  func shortlog() throws -> [AuthorTally] {
    let raw = try run(["shortlog", "-s", "-n", "-e", "HEAD"])
    return GitParsers.parseShortlog(raw)
  }

  /// All tags with creation date and annotated-vs-lightweight flag.
  func tags() throws -> [Tag] {
    let raw = try run([
      "for-each-ref",
      "refs/tags",
      "--format=\(GitParsers.tagFormat)",
    ])
    return GitParsers.parseTags(raw)
  }

  /// File change-count ranking (by raw file-touch frequency, like
  /// `git log --diff-filter=AMD --name-only`). Sorted desc by count.
  func fileChangeCounts(max: Int? = nil) throws -> [FileTally] {
    var args = [
      "log",
      "--no-color",
      "--diff-filter=AMD",
      "--name-only",
      "--pretty=format:\(GitParsers.recordSeparator)",
    ]
    if let max {
      args.append("--max-count=\(max)")
    }
    let raw = try run(args)
    return GitParsers.parseChangedFileCounts(raw)
  }

  /// Topologically ordered commit DAG, laid out into lanes by `GraphLayout`.
  func revList(
    reachableFrom ref: String = "HEAD",
    max: Int = 200
  ) throws -> GraphLayout.Result {
    let raw = try run([
      "rev-list",
      "--topo-order",
      "--parents",
      "--max-count=\(max)",
      ref,
    ])
    let revList = GitParsers.parseRevListParents(raw)
    // Map sha → subject for the same window. Done in one extra call so we
    // can decouple `rev-list --parents` (graph topology) from `log` (subject
    // formatting), which keeps each parser focused on one shape.
    let subjectsRaw = try run([
      "log",
      "--no-color",
      "--pretty=format:%H\(GitParsers.fieldSeparator)%s\(GitParsers.recordSeparator)",
      "--max-count=\(max)",
      ref,
    ])
    let subjects = parseSubjects(subjectsRaw)
    let rows = revList.map { row in
      (sha: row.sha, parents: row.parents, subject: subjects[row.sha] ?? "")
    }
    return GraphLayout.layout(rows: rows)
  }

  // MARK: - Helpers

  private func run(_ arguments: [String]) throws -> String {
    try GitProcess.run(workingDirectory: workingDirectory, arguments: arguments)
  }

  private func formatGitDate(_ date: Date) -> String {
    Self.gitDateFormatter.string(from: date)
  }

  nonisolated(unsafe) private static let gitDateFormatter: ISO8601DateFormatter = {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = [.withFullDate]
    return formatter
  }()

  private func parseSubjects(_ raw: String) -> [String: String] {
    var map: [String: String] = [:]
    for record in raw.components(separatedBy: GitParsers.recordSeparator) {
      let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let fields = trimmed.components(separatedBy: GitParsers.fieldSeparator)
      guard fields.count >= 2 else { continue }
      map[fields[0]] = fields[1]
    }
    return map
  }
}

private extension String {
  /// First non-empty line, trimmed.
  var trimmedLine: String {
    for line in self.split(separator: "\n") {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      if !trimmed.isEmpty { return trimmed }
    }
    return ""
  }

  /// Count of non-empty lines after trimming.
  var lineCount: Int {
    var count = 0
    for line in self.split(separator: "\n") {
      if !line.trimmingCharacters(in: .whitespaces).isEmpty {
        count += 1
      }
    }
    return count
  }
}
