/// A compact key-binding entry used by prototype help surfaces.
public struct PrototypeKeyBinding: Hashable, Sendable, Identifiable {
  public var key: String
  public var label: String
  public var detail: String?

  public var id: String {
    [key, label, detail ?? ""].joined(separator: "\u{001F}")
  }

  public init(
    _ key: String,
    _ label: String,
    detail: String? = nil
  ) {
    self.key = key
    self.label = label
    self.detail = detail
  }
}

/// A compact cluster of help bindings with an optional label.
public struct PrototypeKeyBindingGroup: Hashable, Sendable, Identifiable {
  public var title: String?
  public var bindings: [PrototypeKeyBinding]

  public var id: String {
    [title ?? "", bindings.map(\.id).joined(separator: "|")].joined(
      separator: "\u{001F}"
    )
  }

  public init(
    _ title: String? = nil,
    bindings: [PrototypeKeyBinding]
  ) {
    self.title = title
    self.bindings = bindings
  }
}

/// A terminal-native command entry for searchable command surfaces.
public struct PrototypeCommand: Hashable, Sendable, Identifiable {
  public enum Kind: String, Hashable, Sendable {
    case action
    case navigation
    case toggle
    case destructive

    var symbol: String {
      switch self {
      case .action:
        return "•"
      case .navigation:
        return "→"
      case .toggle:
        return "↕"
      case .destructive:
        return "!"
      }
    }

    var rankingBonus: Int {
      switch self {
      case .action:
        return 2
      case .navigation:
        return 1
      case .toggle:
        return 0
      case .destructive:
        return -1
      }
    }
  }

  public var id: String
  public var title: String
  public var detail: String?
  public var keywords: [String]
  public var shortcut: String?
  public var kind: Kind
  public var isDisabled: Bool

  public init(
    id: String,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    shortcut: String? = nil,
    kind: Kind = .action,
    isDisabled: Bool = false
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.keywords = keywords
    self.shortcut = shortcut
    self.kind = kind
    self.isDisabled = isDisabled
  }
}

/// A lightweight search helper for prototype command palettes.
public struct PrototypeCommandCatalog: Sendable {
  public var commands: [PrototypeCommand]

  public init(_ commands: [PrototypeCommand]) {
    self.commands = commands
  }

  public func matching(
    _ query: String,
    limit: Int? = nil
  ) -> [PrototypeCommand] {
    let normalizedQuery = Self.normalize(query)
    guard !normalizedQuery.isEmpty else {
      return limit.map { Array(commands.prefix(max(0, $0))) } ?? commands
    }

    let tokens = normalizedQuery.split(whereSeparator: { $0.isWhitespace }).map {
      String($0)
    }

    let ranked = commands.compactMap { command -> (PrototypeCommand, Int)? in
      let score = command.score(
        for: normalizedQuery,
        tokens: tokens
      )
      guard score > 0 else {
        return nil
      }
      return (command, score)
    }

    let sorted = ranked.sorted { lhs, rhs in
      if lhs.1 != rhs.1 {
        return lhs.1 > rhs.1
      }
      if lhs.0.title != rhs.0.title {
        return lhs.0.title < rhs.0.title
      }
      return lhs.0.id < rhs.0.id
    }.map(\.0)

    if let limit {
      return Array(sorted.prefix(max(0, limit)))
    }
    return sorted
  }

  private static func normalize(_ value: String) -> String {
    value.lowercased().split(whereSeparator: { $0.isWhitespace }).map {
      String($0)
    }.joined(separator: " ")
  }
}

extension PrototypeCommand {
  fileprivate func score(
    for query: String,
    tokens: [String]
  ) -> Int {
    let normalizedTitle = title.lowercased()
    let normalizedDetail = detail?.lowercased() ?? ""
    let normalizedShortcut = shortcut?.lowercased() ?? ""
    let normalizedKeywords = keywords.map { $0.lowercased() }
    let searchable = [
      id.lowercased(),
      normalizedTitle,
      normalizedDetail,
      normalizedShortcut,
      normalizedKeywords.joined(separator: " "),
    ].joined(separator: " ")

    guard tokens.allSatisfy({ searchable.contains($0) }) else {
      return 0
    }

    var score = 0

    if normalizedTitle == query {
      score += 1000
    }
    if normalizedTitle.hasPrefix(query) {
      score += 800
    }
    if normalizedTitle.contains(query) {
      score += 500
    }
    if normalizedShortcut == query {
      score += 300
    }
    if normalizedShortcut.hasPrefix(query) {
      score += 200
    }
    if normalizedKeywords.contains(where: { $0 == query }) {
      score += 150
    }
    if normalizedKeywords.contains(where: { $0.hasPrefix(query) }) {
      score += 100
    }
    if normalizedDetail.contains(query) {
      score += 50
    }

    score += kind.rankingBonus * 10
    if isDisabled {
      score -= 25
    }

    for token in tokens {
      if normalizedTitle.hasPrefix(token) {
        score += 30
      } else if normalizedTitle.contains(token) {
        score += 15
      }

      if normalizedDetail.contains(token) {
        score += 6
      }
      if normalizedShortcut.contains(token) {
        score += 8
      }
      if normalizedKeywords.contains(where: { $0.contains(token) }) {
        score += 5
      }
    }

    return score
  }
}
