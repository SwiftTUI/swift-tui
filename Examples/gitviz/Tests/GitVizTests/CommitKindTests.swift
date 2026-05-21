import Testing

@testable import GitViz

struct CommitKindTests {
  @Test(
    "Conventional-Commits prefixes classify directly",
    arguments: [
      ("feat: add foo", CommitKind.feat),
      ("fix(api): handle nulls", CommitKind.fix),
      ("refactor(parser)!: rewrite", CommitKind.refactor),
      ("revert: revert previous", CommitKind.revert),
      ("docs(readme): typo", CommitKind.docs),
      ("test: cover edge cases", CommitKind.test),
      ("chore: bump deps", CommitKind.chore),
      ("perf: faster hashing", CommitKind.perf),
      ("ci: gha matrix", CommitKind.ci),
    ]
  )
  func conventionalCommitsPrefix(subject: String, expected: CommitKind) {
    #expect(CommitKind.classify(subject) == expected)
  }

  @Test("Synonyms collapse to canonical kinds")
  func synonyms() {
    #expect(CommitKind.classify("feature: foo") == .feat)
    #expect(CommitKind.classify("bugfix: x") == .fix)
    #expect(CommitKind.classify("build: docker") == .chore)
    #expect(CommitKind.classify("style: ruff") == .chore)
  }

  @Test("Hotfix keyword wins over prefix-less subjects")
  func hotfixKeyword() {
    #expect(CommitKind.classify("Apply a hotfix for the login flow") == .hotfix)
  }

  @Test("Empty / whitespace / merge become .other")
  func otherBuckets() {
    #expect(CommitKind.classify("") == .other)
    #expect(CommitKind.classify("   ") == .other)
    #expect(CommitKind.classify("Merge pull request #42") == .other)
  }

  @Test("Bump / release / revert keyword fallbacks")
  func keywordFallbacks() {
    #expect(CommitKind.classify("Bump version to 1.2.3") == .chore)
    #expect(CommitKind.classify("Release 2.0") == .chore)
    #expect(CommitKind.classify("Revert deadlocking change") == .revert)
  }
}
