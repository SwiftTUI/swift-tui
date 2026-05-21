import Foundation
import Testing

@testable import GitViz

struct GitParsersTests {
  @Test("parseLogWithNumstat decodes 3 commits with insertions/deletions")
  func parsesLogWithNumstat() throws {
    let raw = try loadFixture(named: "log-numstat.txt")
    let commits = GitParsers.parseLogWithNumstat(raw)
    #expect(commits.count == 3)

    #expect(commits[0].sha == "abc1234")
    #expect(commits[0].authorName == "Alice Cooper")
    #expect(commits[0].subject == "feat: add foo")
    #expect(commits[0].insertions == 5)
    #expect(commits[0].deletions == 2)
    #expect(commits[0].parents == ["parent1"])

    #expect(commits[1].sha == "def5678")
    #expect(commits[1].insertions == 12)
    #expect(commits[1].deletions == 1)

    #expect(commits[2].sha == "ff00aa11")
    #expect(commits[2].subject == "docs: readme")
  }

  @Test("parseShortlog returns one tally per row, descending count")
  func parsesShortlog() throws {
    let raw = try loadFixture(named: "shortlog.txt")
    let tallies = GitParsers.parseShortlog(raw)
    #expect(tallies.count == 3)
    #expect(tallies[0].name == "Alice Cooper")
    #expect(tallies[0].email == "alice@example.com")
    #expect(tallies[0].commits == 5)
    #expect(tallies[1].commits == 3)
    #expect(tallies[2].name == "Carol Quinn")
  }

  @Test("parseTags distinguishes annotated from lightweight tags")
  func parsesTags() throws {
    let raw = try loadFixture(named: "for-each-ref-tags.txt")
    let tags = GitParsers.parseTags(raw)
    #expect(tags.count == 3)
    let annotated = tags.filter(\.isAnnotated).map(\.name).sorted()
    let lightweight = tags.filter { !$0.isAnnotated }.map(\.name).sorted()
    #expect(annotated == ["v0.1.0", "v1.0.0"])
    #expect(lightweight == ["v0.2.0"])
  }

  @Test("parseChangedFileCounts ranks paths by frequency")
  func parsesChangedFileCounts() {
    let RS = GitParsers.recordSeparator
    let raw = """
      \(RS)src/foo.swift
      src/bar.swift
      \(RS)src/foo.swift
      \(RS)src/foo.swift
      tests/test.swift
      """
    let counts = GitParsers.parseChangedFileCounts(raw)
    #expect(counts.first?.path == "src/foo.swift")
    #expect(counts.first?.changeCount == 3)
    #expect(counts.count == 3)
  }

  @Test("parseInteger handles trailing whitespace")
  func parsesInteger() {
    #expect(GitParsers.parseInteger("42\n") == 42)
    #expect(GitParsers.parseInteger("  7  ") == 7)
    #expect(GitParsers.parseInteger("nope") == nil)
  }

  // MARK: - Helpers

  private func loadFixture(named name: String) throws -> String {
    let bundle = Bundle.module
    guard let url = bundle.url(forResource: name, withExtension: nil, subdirectory: "Fixtures")
    else {
      throw FixtureError.notFound(name)
    }
    return try String(contentsOf: url, encoding: .utf8)
  }
}

private enum FixtureError: Error, CustomStringConvertible {
  case notFound(String)
  var description: String {
    switch self {
    case .notFound(let name): "fixture not found: \(name)"
    }
  }
}
