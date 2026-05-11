import Foundation

/// Parsers for the canned `git` output formats `GitRepo` consumes.
///
/// All parsers are pure functions over `String` so they can be exercised with
/// fixture files without spawning a subprocess.
enum GitParsers {
  // MARK: - log --pretty=format

  /// Format string we always pass to `git log`. Records are separated by an
  /// ASCII RS (0x1E), fields by ASCII US (0x1F). This avoids collisions with
  /// any character that might appear in commit subjects or author names.
  static let logFormat = "%H\u{1F}%aI\u{1F}%aN\u{1F}%aE\u{1F}%P\u{1F}%s"
  static let recordSeparator = "\u{1E}"
  static let fieldSeparator = "\u{1F}"

  /// Parses output of `git log --pretty=format:<logFormat> --numstat -z`.
  ///
  /// The `-z` flag NUL-terminates numstat path entries. Each commit's
  /// numstat block is a series of `<ins>\t<del>\t<path>\0` lines, where any
  /// of the fields may be `-` for binary diffs.
  static func parseLogWithNumstat(_ raw: String) -> [Commit] {
    var commits: [Commit] = []
    // Split into records first.
    let records = raw.components(separatedBy: recordSeparator)
    for record in records {
      let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }

      // The first 6 fields are the header; numstat lines come after the
      // final field's trailing newline.
      let fields = trimmed.components(separatedBy: fieldSeparator)
      guard fields.count >= 6 else { continue }

      let sha = fields[0]
      let dateString = fields[1]
      let authorName = fields[2]
      let authorEmail = fields[3]
      let parents = fields[4].split(separator: " ").map(String.init)

      // The final field contains "subject\nnumstat lines\0..." — split off
      // the subject line, the rest is numstat (NUL-separated by `-z`).
      let tail = fields[5]
      let (subject, numstatBlock) = splitSubjectAndNumstat(tail)
      let (insertions, deletions) = sumNumstat(numstatBlock)

      guard let date = parseISODate(dateString) else { continue }

      commits.append(
        Commit(
          sha: sha,
          date: date,
          authorName: authorName,
          authorEmail: authorEmail,
          subject: subject,
          parents: parents,
          insertions: insertions,
          deletions: deletions
        )
      )
    }
    return commits
  }

  private static func splitSubjectAndNumstat(_ tail: String) -> (String, String) {
    guard let firstNewline = tail.firstIndex(of: "\n") else {
      return (tail, "")
    }
    let subject = String(tail[..<firstNewline])
    let numstat = String(tail[tail.index(after: firstNewline)...])
    return (subject, numstat)
  }

  private static func sumNumstat(_ block: String) -> (insertions: Int, deletions: Int) {
    guard !block.isEmpty else { return (0, 0) }
    var insertions = 0
    var deletions = 0
    // `-z` separates entries with NUL.
    for entry in block.split(separator: "\u{00}", omittingEmptySubsequences: true) {
      let parts = entry.split(separator: "\t", maxSplits: 2)
      guard parts.count >= 2 else { continue }
      let inserted = parts[0]
      let deleted = parts[1]
      if let inserted = Int(inserted) {
        insertions += inserted
      }
      if let deleted = Int(deleted) {
        deletions += deleted
      }
    }
    return (insertions, deletions)
  }

  /// Reduces a list of commits into per-commit deltas. Drops the parent and
  /// subject fields so downstream code can be pure-numeric.
  static func deltas(from commits: [Commit]) -> [CommitDelta] {
    commits.map { commit in
      CommitDelta(
        sha: commit.sha,
        date: commit.date,
        insertions: commit.insertions,
        deletions: commit.deletions,
        filesChanged: 0  // populated when needed by `--numstat` counts.
      )
    }
  }

  // MARK: - shortlog -s -n -e

  /// Parses `git shortlog -s -n -e` output: `   N\tName <email>`.
  static func parseShortlog(_ raw: String) -> [AuthorTally] {
    var tallies: [AuthorTally] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      // Split into "<commits>\t<rest>". `\t` may be replaced by runs of
      // whitespace, so be lenient.
      let parts = trimmed.split(maxSplits: 1, omittingEmptySubsequences: true) {
        $0 == "\t" || $0 == " "
      }
      guard parts.count == 2, let count = Int(parts[0]) else { continue }
      let rest = String(parts[1])
      let (name, email) = parseNameEmail(rest)
      tallies.append(AuthorTally(name: name, email: email, commits: count))
    }
    return tallies
  }

  private static func parseNameEmail(_ rest: String) -> (String, String) {
    if let open = rest.lastIndex(of: "<"),
      let close = rest.lastIndex(of: ">"),
      open < close
    {
      let name = String(rest[..<open]).trimmingCharacters(in: .whitespaces)
      let email = String(rest[rest.index(after: open)..<close])
      return (name, email)
    }
    return (rest.trimmingCharacters(in: .whitespaces), "")
  }

  // MARK: - for-each-ref refs/tags

  /// Format string for `git for-each-ref refs/tags`. Fields are separated by
  /// US, records by RS.
  static let tagFormat =
    "%(refname:short)\u{1F}%(objectname)\u{1F}%(taggerdate:iso-strict)\u{1F}%(committerdate:iso-strict)\u{1F}%(objecttype)\u{1E}"

  /// Parses `git for-each-ref refs/tags --format=<tagFormat>` output.
  ///
  /// Annotated tags carry their own `taggerdate` and `objecttype=tag`;
  /// lightweight tags point straight at the commit, so `taggerdate` is
  /// empty and we fall back to `committerdate`.
  static func parseTags(_ raw: String) -> [Tag] {
    var tags: [Tag] = []
    for record in raw.components(separatedBy: recordSeparator) {
      let trimmed = record.trimmingCharacters(in: .whitespacesAndNewlines)
      guard !trimmed.isEmpty else { continue }
      let fields = trimmed.components(separatedBy: fieldSeparator)
      guard fields.count >= 5 else { continue }
      let name = fields[0]
      let sha = fields[1]
      let taggerDate = fields[2]
      let committerDate = fields[3]
      let objectType = fields[4]
      let dateString = taggerDate.isEmpty ? committerDate : taggerDate
      guard let date = parseISODate(dateString) else { continue }
      tags.append(
        Tag(
          name: name,
          sha: sha,
          date: date,
          isAnnotated: objectType == "tag"
        )
      )
    }
    return tags
  }

  // MARK: - rev-list --parents

  /// Parses `git rev-list --topo-order --parents <ref>` output. Each line is
  /// `<sha> [<parent1> <parent2>...]`.
  static func parseRevListParents(_ raw: String) -> [(sha: String, parents: [String])] {
    var rows: [(String, [String])] = []
    for line in raw.split(separator: "\n", omittingEmptySubsequences: true) {
      let trimmed = line.trimmingCharacters(in: .whitespaces)
      guard !trimmed.isEmpty else { continue }
      let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
      guard let first = parts.first else { continue }
      let sha = String(first)
      let parents = parts.dropFirst().map(String.init)
      rows.append((sha, parents))
    }
    return rows
  }

  // MARK: - log --diff-filter=AMD --name-only

  /// Parses `git log --diff-filter=AMD --name-only --pretty=format:<RS>` and
  /// returns per-file change counts. Each record (RS-separated) is a list
  /// of changed paths (newline-separated).
  static func parseChangedFileCounts(_ raw: String) -> [FileTally] {
    var counts: [String: Int] = [:]
    for record in raw.components(separatedBy: recordSeparator) {
      for line in record.split(separator: "\n", omittingEmptySubsequences: true) {
        let path = String(line).trimmingCharacters(in: .whitespaces)
        guard !path.isEmpty else { continue }
        counts[path, default: 0] += 1
      }
    }
    return
      counts
      .map { FileTally(path: $0.key, changeCount: $0.value) }
      .sorted { lhs, rhs in
        if lhs.changeCount != rhs.changeCount {
          return lhs.changeCount > rhs.changeCount
        }
        return lhs.path < rhs.path
      }
  }

  // MARK: - rev-list --count

  /// Parses a single-line integer output (e.g. `git rev-list --count HEAD`).
  static func parseInteger(_ raw: String) -> Int? {
    Int(raw.trimmingCharacters(in: .whitespacesAndNewlines))
  }

  // MARK: - date helpers

  /// Parses an ISO-8601 timestamp from git (`%aI` / `iso-strict`).
  static func parseISODate(_ value: String) -> Date? {
    if let parsed = isoDateFormatter(formatOptions: [.withInternetDateTime]).date(from: value) {
      return parsed
    }
    // git sometimes emits "1970-01-01T00:00:00+00:00" — accept the common
    // variants without timezone fractional seconds.
    if let parsed = isoDateFormatter(
      formatOptions: [
        .withYear, .withMonth, .withDay,
        .withTime, .withColonSeparatorInTime, .withDashSeparatorInDate,
        .withTimeZone, .withColonSeparatorInTimeZone,
        .withSpaceBetweenDateAndTime,
      ]
    ).date(from: value) {
      return parsed
    }
    return nil
  }

  private static func isoDateFormatter(
    formatOptions: ISO8601DateFormatter.Options
  ) -> ISO8601DateFormatter {
    let formatter = ISO8601DateFormatter()
    formatter.formatOptions = formatOptions
    return formatter
  }
}
