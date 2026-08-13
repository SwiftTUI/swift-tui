// The framework's default palette rendering.
//
// Moved verbatim from the gallery's `CommandPaletteList` (control-style
// A5). It is deliberately INTERNAL: at 0.9.0 a palette is a declaration
// plus command data plus this rendering, and the public `PaletteStyle`
// protocol that would let an application replace it is Phase B work.
//
// The fuzzy score at the bottom of this file is normative by fixture —
// the gallery's cell-for-cell battery pins its observable ranking, so a
// later refactor cannot silently reorder results.


/// A fuzzy-filterable command-palette list used inside the Gallery's
/// palette sheet. The outer wrapper intentionally returns a
/// single-child `Group` so the stateful body becomes a DECLARED child
/// instead of the deferred payload's root view. In the graph-backed
/// runtime path, declared children are resolved through `resolveView`,
/// which gives the child its own `viewNode` and therefore safe local
/// `@State` / `@FocusState` storage.
///
/// Commands are passed in by the framework — `.paletteSheet`'s content
/// closure receives the snapshot of `paletteCommand` contributions
/// absorbed from the host scope's subtree (mirroring how
/// `.toolbar()` absorbs toolbar items).
struct DefaultPaletteBody: View {
  let commands: [ActivePaletteCommand]
  /// Stored as the binding plus its authoring context rather than a
  /// pre-built closure: a closure minted on every declaration evaluation
  /// makes this view value differ each resolve.
  let isPresented: Binding<Bool>
  let dismissAuthoringContext: AuthoringContext?

  private var dismiss: @MainActor @Sendable () -> Void {
    { [isPresented, dismissAuthoringContext] in
      withAuthoringContext(dismissAuthoringContext) {
        isPresented.wrappedValue = false
      }
    }
  }

  var body: some View {
    Group {
      DefaultPaletteBodyContent(
        commands: commands,
        dismiss: dismiss
      )
    }
  }
}

private struct DefaultPaletteBodyContent: View {
  private static let maximumVisibleRows = 12

  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  @State private var query = ""
  @State private var selectedCommandKey: DefaultPaletteCommandKey?
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

  private var matchKeys: [DefaultPaletteCommandKey] {
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
    for command: ActivePaletteCommand,
    isSelected: Bool
  ) -> some View {
    Button {
      perform(command)
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
    .focusable(false)
    .onTapGesture {
      perform(command)
    }
    .disabled(!command.isEnabled)
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
    perform(command)
  }

  private func perform(_ command: ActivePaletteCommand) {
    guard command.isEnabled else { return }
    command.action()
    dismiss()
  }

  private func reconcileSelection(for keys: [DefaultPaletteCommandKey]) {
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

private struct DefaultPaletteCommandKey: Equatable, Hashable {
  var name: String
  var description: String?
}

private struct DefaultPaletteMatch {
  let command: ActivePaletteCommand
  let score: Int

  var key: DefaultPaletteCommandKey {
    DefaultPaletteCommandKey(
      name: command.name,
      description: command.description
    )
  }
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
