import Foundation

/// A coarse classification of a commit subject line.
///
/// Inferred as a pure function over `Commit.subject`:
/// Conventional-Commits prefix first, then a keyword regex fallback
/// (`hotfix`, `revert`, `bump`, …).
enum CommitKind: String, Sendable, Hashable, CaseIterable {
  case feat
  case fix
  case hotfix
  case refactor
  case revert
  case docs
  case test
  case chore
  case perf
  case ci
  case other

  /// Classifies a commit subject. Empty / whitespace-only subjects become
  /// `.other`.
  static func classify(_ subject: String) -> CommitKind {
    let trimmed = subject.trimmingCharacters(in: .whitespaces)
    guard !trimmed.isEmpty else { return .other }
    let lowered = trimmed.lowercased()

    // Conventional-Commits prefix: `type(scope)?!?:` at the start.
    // We accept the common types plus a few synonyms (e.g. `style`, `build`).
    if let prefix = conventionalPrefix(lowered) {
      switch prefix {
      case "feat", "feature": return .feat
      case "fix", "bugfix": return .fix
      case "hotfix": return .hotfix
      case "refactor", "refact": return .refactor
      case "revert": return .revert
      case "docs", "doc": return .docs
      case "test", "tests": return .test
      case "chore", "build", "style": return .chore
      case "perf", "performance": return .perf
      case "ci", "ops": return .ci
      default: break
      }
    }

    // Keyword fallback.
    if lowered.contains("hotfix") { return .hotfix }
    if lowered.hasPrefix("revert ") || lowered.contains("\nrevert ") {
      return .revert
    }
    if lowered.hasPrefix("merge ") {
      return .other
    }
    if lowered.contains("bump") || lowered.hasPrefix("release ") {
      return .chore
    }

    return .other
  }

  /// Returns the conventional-commits type token at the start of `lowered`,
  /// or `nil` if the subject is not in `<type>(<scope>)?!?: …` form.
  private static func conventionalPrefix(_ lowered: String) -> String? {
    var index = lowered.startIndex
    var letters: [Character] = []
    while index < lowered.endIndex {
      let ch = lowered[index]
      if ch.isLetter {
        letters.append(ch)
        index = lowered.index(after: index)
      } else {
        break
      }
    }
    guard !letters.isEmpty else { return nil }

    // Optional `(scope)` block.
    if index < lowered.endIndex, lowered[index] == "(" {
      guard let close = lowered[index...].firstIndex(of: ")") else { return nil }
      index = lowered.index(after: close)
    }
    // Optional `!`.
    if index < lowered.endIndex, lowered[index] == "!" {
      index = lowered.index(after: index)
    }
    // Mandatory `:`.
    guard index < lowered.endIndex, lowered[index] == ":" else { return nil }
    return String(letters)
  }
}
