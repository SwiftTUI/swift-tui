import SwiftTUICore

/// A fuzzy filter, keyboard selection, and up to twelve visible command rows.
public struct DefaultPaletteStyle: PaletteStyle {
  public init() {}
  public var snapshotLabel: String { "AnyPaletteStyle.automatic" }
  @MainActor public func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    DefaultPaletteStyleBody(configuration: configuration)
  }
}
extension PaletteStyle where Self == DefaultPaletteStyle {
  public static var automatic: Self { .init() }
}
extension DefaultPaletteStyle: ReuseTransparentStyle {}

private struct DefaultPaletteStyleBody: View {
  private static let maximumVisibleRows = 12

  let configuration: PaletteStyleConfiguration
  private var commands: [PaletteStyleConfiguration.Command] { configuration.commands }

  @State private var query = ""
  @State private var selectedCommandKey: AnyID?
  @FocusState private var isQueryFocused: Bool
  @Namespace private var filterFocusNamespace

  private var matches: [DefaultPaletteMatch] {
    if query.isEmpty {
      return commands.enumerated().map { offset, command in
        DefaultPaletteMatch(command: command, score: offset)
      }
    }
    return
      commands
      .compactMap { command in
        fuzzyMatchScore(query: query, against: command.name)
          .map { DefaultPaletteMatch(command: command, score: $0) }
      }
      .sorted { $0.score < $1.score }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      TextField("Filter commands…", text: $query)
        .focused($isQueryFocused)
        .prefersDefaultFocus(in: filterFocusNamespace)
        .onKeyPress(perform: handleFilterKeyPress)
      Divider()
      matchList
    }
    .padding(1)
    .frame(minWidth: 44, alignment: .leading)
    .focusScope(filterFocusNamespace)
    .onAppear {
      query = ""
    }
    .onChange(of: matchKeys, initial: true) { _, newKeys in
      reconcileSelection(for: newKeys)
    }
  }

  @ViewBuilder
  private var matchList: some View {
    // `matches` runs the full fuzzy filter + sort over every command, so it is
    // computed exactly once here and the selected index is derived from that
    // same array — rather than recomputing it per row (via the old computed
    // `effectiveSelectedIndex`), which made the body O(visibleRows × commands)
    // on every keystroke.
    let rows = matches
    if rows.isEmpty {
      Text(commands.isEmpty ? "No commands in the current scope." : "No matches.")
        .foregroundStyle(.separator)
        .padding(.vertical, 1)
    } else {
      let selected = effectiveSelectedIndex(in: rows)
      let visibleRange = visibleRange(in: rows, selectedIndex: selected ?? 0)
      VStack(alignment: .leading, spacing: 0) {
        ForEach(Array(visibleRange), id: \.self) { index in
          let match = rows[index]
          row(for: match.command, isSelected: index == selected)
        }
      }
    }
  }

  private var matchKeys: [AnyID] {
    matches.map(\.key)
  }

  private func selectedIndex(in rows: [DefaultPaletteMatch]) -> Int? {
    guard let selectedCommandKey else { return nil }
    return rows.firstIndex { $0.key == selectedCommandKey }
  }

  private func effectiveSelectedIndex(in rows: [DefaultPaletteMatch]) -> Int? {
    selectedIndex(in: rows) ?? (rows.isEmpty ? nil : 0)
  }

  private func visibleRange(
    in rows: [DefaultPaletteMatch],
    selectedIndex: Int
  ) -> Range<Int> {
    guard rows.count > Self.maximumVisibleRows else {
      return 0..<rows.count
    }

    let start = min(
      max(0, selectedIndex - Self.maximumVisibleRows + 1),
      rows.count - Self.maximumVisibleRows
    )
    return start..<(start + Self.maximumVisibleRows)
  }

  private func row(
    for command: PaletteStyleConfiguration.Command,
    isSelected: Bool
  ) -> some View {
    command.route {
      Button {
        command.perform()
      } label: {
        HStack(spacing: 1) {
          Text(isSelected ? ">" : " ")
            .foregroundStyle(isSelected ? .tint : .background)
          Text(command.name)
          if let description = command.description {
            Spacer()
            Text(description).foregroundStyle(.separator)
          }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background {
          if isSelected {
            Rectangle().fill(.selection)
          }
        }
      }
      .buttonStyle(.plain)
      .accessibilityLabel(command.name)
      .focusable(false)
      .disabled(!command.isEnabled)
    }
  }

  private func handleFilterKeyPress(_ keyPress: KeyPress) -> KeyPressResult {
    if keyPress.modifiers == [] {
      switch keyPress.key {
      case .arrowDown, .tab:
        moveSelection(by: 1)
        return .handled
      case .arrowUp:
        moveSelection(by: -1)
        return .handled
      case .return:
        openSelectedCommand()
        return .handled
      default:
        return .ignored
      }
    }

    if keyPress == KeyPress(.tab, modifiers: .shift) {
      moveSelection(by: -1)
      return .handled
    }
    return .ignored
  }

  private func moveSelection(by delta: Int) {
    let rows = matches
    guard !rows.isEmpty else {
      selectedCommandKey = nil
      return
    }

    let currentIndex = effectiveSelectedIndex(in: rows) ?? 0
    let nextIndex = min(max(currentIndex + delta, 0), rows.count - 1)
    selectedCommandKey = rows[nextIndex].key
  }

  private func openSelectedCommand() {
    let rows = matches
    guard
      let selected = effectiveSelectedIndex(in: rows),
      rows.indices.contains(selected)
    else {
      return
    }

    let command = rows[selected].command
    guard command.isEnabled else { return }
    command.perform()
  }

  private func reconcileSelection(for keys: [AnyID]) {
    guard !keys.isEmpty else {
      selectedCommandKey = nil
      return
    }

    if let selectedCommandKey, keys.contains(selectedCommandKey) {
      return
    }
    selectedCommandKey = keys.first
  }
}

private struct DefaultPaletteMatch {
  let command: PaletteStyleConfiguration.Command
  let score: Int

  var key: AnyID { command.id }
}

/// Returns a fuzzy-match score for `query` against `candidate`, or
/// `nil` when the query is not a (case-insensitive) subsequence of
/// `candidate`. Lower scores are better matches.
///
/// The score is the total gap length between matched characters (plus
/// a leading-gap penalty for characters before the first match), so
/// tighter, earlier matches rank above looser, later ones. An empty
/// query matches everything with score 0.
private func fuzzyMatchScore(query: String, against candidate: String) -> Int? {
  guard !query.isEmpty else { return 0 }
  let queryChars = Array(query.lowercased())
  let candidateChars = Array(candidate.lowercased())

  var queryIndex = 0
  var lastMatch: Int? = nil
  var gapPenalty = 0
  for (index, char) in candidateChars.enumerated() {
    guard queryIndex < queryChars.count else { break }
    if char == queryChars[queryIndex] {
      if let lastMatch {
        gapPenalty += index - lastMatch - 1
      } else {
        // Leading gap penalty — tighter prefix matches rank best.
        gapPenalty += index
      }
      lastMatch = index
      queryIndex += 1
    }
  }
  return queryIndex == queryChars.count ? gapPenalty : nil
}
