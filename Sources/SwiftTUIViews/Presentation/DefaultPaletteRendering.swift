import SwiftTUICore

/// A fuzzy filter, keyboard selection, and up to twelve visible command rows.
///
/// The body is a filter field above the matching rows. Typing filters the
/// commands by a case-insensitive subsequence match on
/// ``PaletteStyleConfiguration/Command/name`` alone, ranking tighter and
/// earlier matches first; an empty query keeps contribution order. Down and Tab
/// move the selection forward, Up and Shift-Tab move it back, and Return runs
/// the selected command through
/// ``PaletteStyleConfiguration/Command/perform()``, which also dismisses the
/// palette. The selection is tracked by command identity, so it survives
/// filtering while the selected command still matches and otherwise falls back
/// to the first row.
///
/// At most twelve rows are visible. With the native filter and single-line
/// command rows, the window shrinks to fit short terminals and contains the
/// selection when the terminal has at least eight rows. The window scrolls
/// only when selection leaves it, so reversing direction moves the cursor
/// within the existing rows. Each row is a pointer-routed button showing the
/// command's name with its description trailing in the separator paint, marked and filled
/// with the selection paint when selected, and rendered disabled when the
/// contribution is. With no commands in scope, or no match for the query, the
/// body says so in place of the rows.
///
/// See <doc:Commands-And-Key-Input>.
public struct DefaultPaletteStyle: PaletteStyle {
  /// Creates the style.
  public init() {}
  /// The label reported in snapshots and diagnostics,
  /// `"AnyPaletteStyle.automatic"`.
  public var snapshotLabel: String { "AnyPaletteStyle.automatic" }
  /// Returns the filter field, a divider, and the visible command rows.
  ///
  /// - Parameter configuration: The palette's title, its commands, and the
  ///   render state.
  /// - Returns: The default palette body.
  @MainActor public func makeBody(configuration: PaletteStyleConfiguration) -> some View {
    DefaultPaletteStyleBody(configuration: configuration)
  }
}
extension PaletteStyle where Self == DefaultPaletteStyle {
  /// The framework palette; see ``DefaultPaletteStyle``.
  public static var automatic: Self { .init() }
}
extension DefaultPaletteStyle: ReuseTransparentStyle {}

private struct DefaultPaletteStyleBody: View {
  let configuration: PaletteStyleConfiguration
  private var commands: [PaletteStyleConfiguration.Command] { configuration.commands }
  private var maximumVisibleRows: Int {
    // The native dropdown adds two inset rows. This body adds two padding
    // rows, the default three-row filter, and a divider. Its twenty-row
    // viewport therefore fits at most twelve single-line commands.
    let availableRows = configuration.terminalSize.height - 8
    return min(12, max(1, availableRows))
  }

  @State private var query = ""
  @State private var selectedCommandKey: AnyID?
  @State private var visibleStart = 0
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
      visibleStart = 0
    }
    .onChange(of: matchKeys, initial: true) { _, newKeys in
      reconcileSelection(for: newKeys)
    }
    .onChange(of: maximumVisibleRows) { _, _ in
      reconcileSelection(for: matchKeys)
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
    guard rows.count > maximumVisibleRows else {
      return 0..<rows.count
    }

    let start = windowStart(count: rows.count, selectedIndex: selectedIndex)
    return start..<(start + maximumVisibleRows)
  }

  private func windowStart(count: Int, selectedIndex: Int) -> Int {
    let start = min(max(0, visibleStart), max(0, count - maximumVisibleRows))
    if selectedIndex < start { return selectedIndex }
    if selectedIndex >= start + maximumVisibleRows {
      return selectedIndex - maximumVisibleRows + 1
    }
    return start
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
      visibleStart = 0
      return
    }

    guard let currentIndex = effectiveSelectedIndex(in: rows) else { return }
    var nextIndex = currentIndex + delta
    while rows.indices.contains(nextIndex) {
      if rows[nextIndex].command.isEnabled {
        selectedCommandKey = rows[nextIndex].key
        visibleStart = windowStart(count: rows.count, selectedIndex: nextIndex)
        return
      }
      nextIndex += delta
    }
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
      visibleStart = 0
      return
    }

    let rows = matches
    if let index = effectiveSelectedIndex(in: rows) {
      selectedCommandKey = rows[index].key
      visibleStart = windowStart(count: rows.count, selectedIndex: index)
    } else {
      selectedCommandKey = nil
      visibleStart = 0
    }
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
