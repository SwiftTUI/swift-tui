import Core

// MARK: - Model

/// A command that can be searched, displayed, and executed from a command palette.
public struct Command: Hashable, Sendable, Identifiable {
  /// The visual kind of a command, used for ranking and display.
  public enum Kind: String, Hashable, Sendable {
    case action
    case navigation
    case toggle
    case destructive

    var symbol: String {
      switch self {
      case .action:
        "•"
      case .navigation:
        "→"
      case .toggle:
        "↕"
      case .destructive:
        "!"
      }
    }

    fileprivate var rankingBonus: Int {
      switch self {
      case .action:
        2
      case .navigation:
        1
      case .toggle:
        0
      case .destructive:
        -1
      }
    }

    fileprivate var focusStyle: SemanticStyleRole {
      switch self {
      case .action:
         .tint
      case .destructive: 
        .danger
      case .navigation: 
        .link
      case .toggle: 
        .selection
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

// MARK: - Search

/// Searches and ranks commands by fuzzy relevance to a query.
public struct CommandCatalog: Sendable {
  public var commands: [Command]

  public init(_ commands: [Command]) {
    self.commands = commands
  }

  public func matching(
    _ query: String,
    limit: Int? = nil
  ) -> [Command] {
    let normalizedQuery = Self.normalize(query)
    guard !normalizedQuery.isEmpty else {
      return limit.map { Array(commands.prefix(max(0, $0))) } ?? commands
    }

    let tokens = normalizedQuery.split(whereSeparator: \.isWhitespace).map {
      String($0)
    }

    let ranked = commands.compactMap { command -> (Command, Int)? in
      let score = Self.score(command, for: normalizedQuery, tokens: tokens)
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
    value.lowercased().split(whereSeparator: \.isWhitespace).map {
      String($0)
    }.joined(separator: " ")
  }

  private static func score(
    _ command: Command,
    for query: String,
    tokens: [String]
  ) -> Int {
    let normalizedTitle = command.title.lowercased()
    let normalizedDetail = command.detail?.lowercased() ?? ""
    let normalizedShortcut = command.shortcut?.lowercased() ?? ""
    let normalizedKeywords = command.keywords.map { $0.lowercased() }
    let searchable = [
      command.id.lowercased(),
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

    score += command.kind.rankingBonus * 10
    if command.isDisabled {
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

// MARK: - Preference Key

private struct CommandPreferenceValue: Equatable, Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var commands: [Command] = []

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    commands.map(\.title).joined(separator: ", ")
  }
}

private enum CommandPreferenceKey: PreferenceKey {
  static let defaultValue = CommandPreferenceValue()

  static func reduce(
    value: inout CommandPreferenceValue,
    nextValue: () -> CommandPreferenceValue
  ) {
    value.commands.append(contentsOf: nextValue().commands)
  }
}

// MARK: - View Modifier

extension View {
  /// Registers a command for discovery in the command palette.
  ///
  /// Commands registered via this modifier are collected through the preference
  /// system and made available to any ancestor ``CommandPalette``.
  ///
  /// ```swift
  /// Button("Save") { save() }
  ///   .command(id: "save", title: "Save File", shortcut: "Ctrl+S")
  /// ```
  public func command(
    id: String,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    shortcut: String? = nil,
    kind: Command.Kind = .action,
    isDisabled: Bool = false
  ) -> some View {
    CommandModifier(
      content: self,
      command: Command(
        id: id,
        title: title,
        detail: detail,
        keywords: keywords,
        shortcut: shortcut,
        kind: kind,
        isDisabled: isDisabled
      )
    )
  }
}

private struct CommandModifier<Content: View>: View, ResolvableView {
  var content: Content
  var command: Command

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    node.preferenceValues.merge(
      CommandPreferenceKey.self,
      value: .init(commands: [command])
    )
    return [node]
  }
}

// MARK: - Command Palette View

/// A searchable, scrollable command palette that fuzzy-matches registered commands.
///
/// The palette reads commands from the preference system, filters them by the
/// current query, and displays ranked results. Selecting a command calls the
/// `onExecute` closure and dismisses the palette.
///
/// Typically presented via `.commandPalette(isPresented:onExecute:)`.
public struct CommandPalette: View {
  private let query: Binding<String>
  private let commands: [Command]
  private let placeholder: String
  private let emptyState: String
  private let maximumResults: Int?
  private let onExecute: @MainActor @Sendable (Command) -> Void

  public init(
    query: Binding<String>,
    commands: [Command],
    placeholder: String = "Search commands…",
    emptyState: String = "No matching commands",
    maximumResults: Int? = 8,
    onExecute: @escaping @MainActor @Sendable (Command) -> Void = { _ in }
  ) {
    self.query = query
    self.commands = commands
    self.placeholder = placeholder
    self.emptyState = emptyState
    self.maximumResults = maximumResults
    self.onExecute = onExecute
  }

  public var body: some View {
    let matches = CommandCatalog(commands).matching(
      query.wrappedValue,
      limit: maximumResults
    )

    return VStack(alignment: .leading, spacing: 1) {
      TextField(placeholder, text: query)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if matches.isEmpty {
            Text(emptyState)
              .foregroundStyle(.separator)
          } else {
            ForEach(matches) { command in
              Button(action: {onExecute(command)}) {
                CommandPaletteRow(command: command)
              }
              .buttonStyle(.plain)
              .disabled(command.isDisabled)
            }
          }
        }
      }
    }
  }
}

private struct CommandPaletteRow: View {
  let command: Command

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text(command.kind.symbol)
        .foregroundStyle(.separator)

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(command.title)
          Spacer()
          if let shortcut = command.shortcut, !shortcut.isEmpty {
            Text(shortcut)
              .foregroundStyle(.separator)
          }
        }

        if let detail = command.detail, !detail.isEmpty {
          Text(detail)
            .foregroundStyle(.separator)
        }
      }
    }
    .opacity(command.isDisabled ? 0.6 : 1)
  }
}

// MARK: - Convenience Modifier

extension View {
  /// Presents a command palette as a sheet, auto-populated from all `.command()`
  /// registrations in the subtree.
  ///
  /// ```swift
  /// ContentView()
  ///   .commandPalette(isPresented: $showPalette) { command in
  ///     handleCommand(command)
  ///   }
  /// ```
  public func commandPalette(
    isPresented: Binding<Bool>,
    placeholder: String = "Search commands…",
    onExecute: @escaping @MainActor @Sendable (Command) -> Void
  ) -> some View {
    CommandPaletteModifier(
      content: self,
      isPresented: isPresented,
      placeholder: placeholder,
      onExecute: onExecute
    )
  }
}

private struct CommandPaletteModifier<Content: View>: View, ResolvableView {
  var content: Content
  var isPresented: Binding<Bool>
  var placeholder: String
  var onExecute: @MainActor @Sendable (Command) -> Void

  @State private var query = ""

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    resolveViewElements(body, in: context)
  }

  var body: some View {
    content
      .overlayPreferenceValue(CommandPreferenceKey.self) { preference in
        Group {
          if isPresented.wrappedValue {
            Rectangle().fill(.background)
          } else {
            EmptyView()
          }
        }
          .sheet("Command Palette", isPresented: isPresented) {
            CommandPalette(
              query: Binding(
                get: { query },
                set: { query = $0 }
              ),
              commands: preference.commands,
              placeholder: placeholder
            ) { [isPresented, onExecute] command in
              isPresented.wrappedValue = false
              query = ""
              onExecute(command)
            }
          }
      }
  }
}
