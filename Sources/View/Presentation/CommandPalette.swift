public import Core

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

    fileprivate var focusTone: TerminalTone {
      switch self {
      case .action:
        .accent
      case .destructive:
        .danger
      case .navigation:
        .info
      case .toggle:
        .warning
      }
    }
  }

  public var id: String
  public var title: String
  public var detail: String?
  public var keywords: [String]
  public var kind: Kind
  public var isDisabled: Bool

  public init(
    id: String,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Kind = .action,
    isDisabled: Bool = false
  ) {
    self.id = id
    self.title = title
    self.detail = detail
    self.keywords = keywords
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
    let normalizedKeywords = command.keywords.map { $0.lowercased() }
    let searchable = [
      command.id.lowercased(),
      normalizedTitle,
      normalizedDetail,
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
      if normalizedKeywords.contains(where: { $0.contains(token) }) {
        score += 5
      }
    }

    return score
  }
}

// MARK: - Preference Key

private struct CommandRegistration: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var command: Command
  var action: (@MainActor @Sendable () -> Void)?

  init(
    command: Command,
    action: (@MainActor @Sendable () -> Void)? = nil
  ) {
    self.command = command
    self.action = action
  }

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    "CommandRegistration(id: \(String(reflecting: command.id)), hasAction: \(action != nil))"
  }
}

private struct CommandPreferenceValue: Sendable,
  CustomStringConvertible,
  CustomDebugStringConvertible
{
  var registrations: [CommandRegistration] = []

  var description: String {
    debugDescription
  }

  var debugDescription: String {
    registrations.map(\.command.title).joined(separator: ", ")
  }
}

private enum CommandPreferenceKey: PreferenceKey {
  static let defaultValue = CommandPreferenceValue()

  static func reduce(
    value: inout CommandPreferenceValue,
    nextValue: () -> CommandPreferenceValue
  ) {
    value.registrations.append(contentsOf: nextValue().registrations)
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
  ///   .command(id: "save", title: "Save File")
  /// ```
  public func command(
    id: String,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Command.Kind = .action,
    isDisabled: Bool = false
  ) -> some View {
    CommandModifier(
      content: self,
      registration: CommandRegistration(
        command: Command(
          id: id,
          title: title,
          detail: detail,
          keywords: keywords,
          kind: kind,
          isDisabled: isDisabled
        )
      )
    )
  }

  /// Registers a command with an action closure for discovery and execution in
  /// the command palette.
  ///
  /// Use this when the command does not correspond to a currently rendered
  /// focusable view, but should still be searchable and invokable.
  ///
  /// ```swift
  /// ContentView()
  ///   .command(id: "new-window", title: "New Window") {
  ///     openNewWindow()
  ///   }
  /// ```
  public func command(
    id: String,
    title: String,
    detail: String? = nil,
    keywords: [String] = [],
    kind: Command.Kind = .action,
    isDisabled: Bool = false,
    action: @escaping @MainActor @Sendable () -> Void
  ) -> some View {
    CommandModifier(
      content: self,
      registration: CommandRegistration(
        command: Command(
          id: id,
          title: title,
          detail: detail,
          keywords: keywords,
          kind: kind,
          isDisabled: isDisabled
        ),
        action: action
      )
    )
  }
}

private struct CommandModifier<Content: View>: View, ResolvableView {
  var content: Content
  var registration: CommandRegistration

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)
    let dynamicPropertyScope = currentAuthoringContext()
    let resolvedAction = registration.action.map { action in
      { @MainActor in
        if let dynamicPropertyScope {
          withAuthoringContext(dynamicPropertyScope) {
            action()
          }
        } else {
          action()
        }
      }
    }
    node.preferenceValues.merge(
      CommandPreferenceKey.self,
      value: .init(
        registrations: [
          .init(
            command: registration.command,
            action: resolvedAction
          )
        ]
      )
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
  private let onDismiss: @MainActor @Sendable () -> Void
  private let onExecute: @MainActor @Sendable (Command) -> Void
  @State private var selectedCommandID: String?

  public init(
    query: Binding<String>,
    commands: [Command],
    placeholder: String = "Search commands…",
    emptyState: String = "No matching commands",
    maximumResults: Int? = 8,
    onDismiss: @escaping @MainActor @Sendable () -> Void = {},
    onExecute: @escaping @MainActor @Sendable (Command) -> Void = { _ in }
  ) {
    let authoringScope = currentAuthoringContext()
    self.query = query
    self.commands = commands
    self.placeholder = placeholder
    self.emptyState = emptyState
    self.maximumResults = maximumResults
    self.onDismiss = {
      if let authoringScope {
        withAuthoringContext(authoringScope) {
          onDismiss()
        }
      } else {
        onDismiss()
      }
    }
    self.onExecute = { command in
      if let authoringScope {
        withAuthoringContext(authoringScope) {
          onExecute(command)
        }
      } else {
        onExecute(command)
      }
    }
  }

  public var body: some View {
    let matches = matchingCommands(for: query.wrappedValue)
    let highlightedCommandID = preferredSelectedCommandID(in: matches)
    VStack(alignment: .leading, spacing: 1) {
      TextField(placeholder, text: query)
        .focusable(false)
      ScrollView(.vertical) {
        VStack(alignment: .leading, spacing: 0) {
          if matches.isEmpty {
            Text(emptyState)
              .foregroundStyle(.separator)
          } else {
            ForEach(matches) { command in
              Button(action: {
                activate(command)
              }) {
                CommandPaletteRow(
                  command: command,
                  isSelected: highlightedCommandID == command.id
                )
              }
              .buttonStyle(.plain)
              .focusable(false)
              .disabled(command.isDisabled)
            }
          }
        }
      }
      .focusScope()
    }
    .background(.background)
    .onKeyPress { keyPress in
      handleKeyPress(keyPress, matches: matches)
    }
  }

  @MainActor
  private func matchingCommands(
    for query: String
  ) -> [Command] {
    CommandCatalog(commands).matching(
      query,
      limit: maximumResults
    )
  }

  @MainActor
  private func activate(
    _ command: Command
  ) {
    guard !command.isDisabled else {
      return
    }
    onDismiss()
    onExecute(command)
  }

  @MainActor
  private func handleKeyPress(
    _ keyPress: KeyPress,
    matches: [Command]
  ) -> KeyPressResult {
    switch keyPress.key {
    case .escape where keyPress.modifiers.isEmpty:
      onDismiss()
      return .handled
    case .return where keyPress.modifiers.isEmpty:
      if let command = selectedCommand(in: matches) {
        activate(command)
      }
      return .handled
    case .arrowDown where keyPress.modifiers.isEmpty:
      moveSelection(in: matches, direction: .down)
      return .handled
    case .arrowUp where keyPress.modifiers.isEmpty:
      moveSelection(in: matches, direction: .up)
      return .handled
    case .character, .space,
      .backspace where allowsPaletteTextEntry(keyPress):
      _ = mutateTextEntryBinding(
        query,
        event: keyPress.key,
        allowsNewlines: false,
        scrollPosition: nil
      )
      syncSelection(
        in: matchingCommands(for: query.wrappedValue)
      )
      return .handled
    default:
      return .ignored
    }
  }

  @MainActor
  private func moveSelection(
    in matches: [Command],
    direction: SelectionDirection
  ) {
    let enabledMatches = matches.filter { !$0.isDisabled }
    guard !enabledMatches.isEmpty else {
      selectedCommandID = nil
      return
    }

    guard let currentSelectionID = preferredSelectedCommandID(in: matches),
      let currentIndex = enabledMatches.firstIndex(where: { $0.id == currentSelectionID })
    else {
      selectedCommandID = enabledMatches.first?.id
      return
    }

    let nextIndex: Int
    switch direction {
    case .down:
      nextIndex = min(currentIndex + 1, enabledMatches.count - 1)
    case .up:
      nextIndex = max(currentIndex - 1, 0)
    }
    selectedCommandID = enabledMatches[nextIndex].id
  }

  @MainActor
  private func syncSelection(
    in matches: [Command]
  ) {
    let preferredCommandID = preferredSelectedCommandID(in: matches)
    guard selectedCommandID != preferredCommandID else {
      return
    }
    selectedCommandID = preferredCommandID
  }

  @MainActor
  private func selectedCommand(
    in matches: [Command]
  ) -> Command? {
    guard let selectedCommandID = preferredSelectedCommandID(in: matches) else {
      return nil
    }
    return matches.first(where: { $0.id == selectedCommandID })
  }

  @MainActor
  private func preferredSelectedCommandID(
    in matches: [Command]
  ) -> String? {
    let enabledMatches = matches.filter { !$0.isDisabled }
    if let selectedCommandID,
      enabledMatches.contains(where: { $0.id == selectedCommandID })
    {
      return selectedCommandID
    }
    return enabledMatches.first?.id
  }

  private func allowsPaletteTextEntry(
    _ keyPress: KeyPress
  ) -> Bool {
    switch keyPress.key {
    case .character:
      return keyPress.modifiers.isEmpty || keyPress.modifiers == .shift
    case .space, .backspace:
      return keyPress.modifiers.isEmpty
    default:
      return false
    }
  }
}

private struct CommandPaletteRow: View {
  let command: Command
  let isSelected: Bool

  var body: some View {
    HStack(alignment: .firstTextBaseline, spacing: 1) {
      Text(command.kind.symbol)
        .foregroundStyle(.separator)

      VStack(alignment: .leading, spacing: 0) {
        HStack(alignment: .firstTextBaseline, spacing: 1) {
          Text(command.title)
          Spacer()
        }

        if let detail = command.detail, !detail.isEmpty {
          Text(detail)
            .foregroundStyle(.separator)
        }
      }
    }
    .padding(.init(horizontal: 1, vertical: 0))
    .background {
      if isSelected {
        Rectangle().fill(
          AnyShapeStyle(
            .terminalRow(command.kind.focusTone, isSelected: true)
          )
        )
      }
    }
    .opacity(command.isDisabled ? 0.6 : 1)
  }
}

private enum SelectionDirection {
  case up
  case down
}

// MARK: - Convenience Modifier

extension View {
  /// Presents a command palette as a sheet, auto-populated from all `.command()`
  /// registrations in the subtree.
  ///
  /// ```swift
  /// ContentView()
  ///   .commandPalette(
  ///     isPresented: $showPalette,
  ///     shortcut: .character("/")
  ///   ) { command in
  ///     handleCommand(command)
  ///   }
  /// ```
  public func commandPalette(
    isPresented: Binding<Bool>,
    placeholder: String = "Search commands…",
    shortcut: KeyEvent? = nil,
    shortcutModifiers: EventModifiers = [],
    onExecute: @escaping @MainActor @Sendable (Command) -> Void = { _ in }
  ) -> some View {
    CommandPaletteModifier(
      content: self,
      isPresented: isPresented,
      placeholder: placeholder,
      shortcut: shortcut,
      shortcutModifiers: shortcutModifiers,
      onExecute: onExecute
    )
  }
}

private struct CommandPaletteModifier<Content: View>: View, ResolvableView {
  var content: Content
  var isPresented: Binding<Bool>
  var placeholder: String
  var shortcut: KeyEvent?
  var shortcutModifiers: EventModifiers
  var onExecute: @MainActor @Sendable (Command) -> Void

  @State private var query = ""

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var node = content.resolve(in: context)

    if let shortcut, !isPresented.wrappedValue {
      let binding = HotkeyBinding(
        key: KeyPress(shortcut, modifiers: shortcutModifiers)
      )
      context.hotkeyRegistry?.register(identity: context.identity, binding: binding) {
        localKeyPress in
        guard
          localKeyPress.key == shortcut,
          localKeyPress.modifiers == shortcutModifiers
        else {
          return false
        }
        isPresented.wrappedValue = true
        return true
      }
    }

    guard isPresented.wrappedValue else {
      return [node]
    }

    let registrations = node.preferenceValues[CommandPreferenceKey.self].registrations
    node.preferenceValues.merge(
      TerminalPresentationPreferenceKey.self,
      value: .init(
        requests: [
          .init(
            attachmentIdentity: node.identity,
            title: "Command Palette",
            kind: .sheet,
            backdropOpacity: 0.7,
            actionPayloads: [],
            messagePayloads: [],
            contentPayloads: deferredDeclaredBuilderChildren(
              from: paletteSheet(for: registrations)
            ),
            dismiss: { [isPresented] in
              isPresented.wrappedValue = false
              query = ""
            }
          )
        ]
      )
    )

    return [node]
  }

  private func paletteSheet(
    for registrations: [CommandRegistration]
  ) -> some View {
    let commands = registrations.map(\.command)
    return CommandPalette(
      query: Binding(
        get: { query },
        set: { query = $0 }
      ),
      commands: commands,
      placeholder: placeholder,
      onDismiss: { [isPresented] in
        isPresented.wrappedValue = false
        query = ""
      }
    ) { command in
      execute(command, using: registrations)
    }
  }

  @MainActor
  private func execute(
    _ command: Command,
    using registrations: [CommandRegistration]
  ) {
    if let action = registrations.first(where: { $0.command == command })?.action {
      action()
      return
    }
    onExecute(command)
  }
}
