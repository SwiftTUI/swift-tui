import TerminalUI

/// A fuzzy-filterable command-palette list used inside the Gallery's
/// palette sheet. Renders a text field at the top that drives a
/// subsequence-based fuzzy filter over the supplied commands; each
/// match is a button that fires the captured action and dismisses the
/// palette.
///
/// The commands are passed in explicitly (rather than read from the
/// environment) because opening the palette as a sheet moves focus
/// into the overlay tree, where the scope chain no longer includes
/// the Gallery's Panel. The caller snapshots `activePaletteCommands`
/// at the moment the palette opens and passes that snapshot through
/// — so the list reflects "what was visible when the user invoked
/// the palette", which is the right UX for a command palette.
/// Important: this view must NOT declare its own `@State` or
/// `@FocusState` wrappers. Sheet content is resolved inside the
/// parent view's authoring context (see `View.resolveBody` in
/// `State.swift:383` and `ScopedBuilder` — deferred payloads inherit
/// the sheet-creating view's context). Local property wrappers here
/// would route state-slot lookups through the PARENT's viewNode,
/// colliding with its real `@State` slots by source-line ordinal and
/// triggering `ViewNode.stateSlot` type-mismatch fatalError. All
/// mutable palette state (query text, focus binding) lives on
/// `GalleryView` and is threaded here as `Binding`s.
struct CommandPaletteList: View {
  let commands: [ActivePaletteCommand]
  let query: Binding<String>
  let isQueryFocused: FocusState<Bool>.Binding
  let dismiss: @MainActor @Sendable () -> Void

  private var matches: [(command: ActivePaletteCommand, score: Int)] {
    let queryText = query.wrappedValue
    if queryText.isEmpty {
      return commands.enumerated().map { ($0.element, $0.offset) }
    }
    return
      commands
      .compactMap { command in
        fuzzyMatchScore(query: queryText, against: command.name)
          .map { (command: command, score: $0) }
      }
      .sorted { $0.score < $1.score }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      diagnosticRow
      TextField("Filter commands…", text: query)
        .focused(isQueryFocused)
        .onAppear {
          // Belt-and-braces: parent already sets
          // `isPaletteQueryFocused = true` in `openPalette()`, but
          // if the user re-presents the same sheet without going
          // through that path, this onAppear still grabs focus.
          isQueryFocused.wrappedValue = true
        }
      Divider()
      matchList
      Divider()
      footer
    }
    .padding(1)
    .frame(minWidth: 44, alignment: .leading)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("Command palette").bold()
      Spacer()
      Text("Tab + Enter to run")
        .foregroundStyle(.separator)
    }
  }

  // Visible diagnostic row. Remove once the palette is working
  // end-to-end in the gallery; kept for now so the user can see at a
  // glance whether the snapshot reached the sheet and whether the
  // text field is holding focus.
  private var diagnosticRow: some View {
    HStack(spacing: 2) {
      Text("debug:")
      Text("cmds=\(commands.count)")
      Text("match=\(matches.count)")
      Text("focus=\(isQueryFocused.wrappedValue ? "yes" : "no")")
      Spacer()
    }
    .foregroundStyle(.separator)
  }

  // Footer with an explicit Close button. The framework's Esc-closes-
  // presentation behavior was removed in Phase 0 of the ActionScopes
  // rewrite and has not yet been reinstated (see
  // Tests/TerminalUITests/AppRuntimeTests.swift:225 — "Escape-owned
  // presentation dismissal returns in Phase 3"). Until the framework
  // gap closes, an explicit Cancel button is the reliable dismissal
  // affordance.
  private var footer: some View {
    HStack(spacing: 2) {
      Spacer()
      Button("Cancel", role: .cancel) {
        dismiss()
      }
    }
  }

  @ViewBuilder
  private var matchList: some View {
    let rows = matches
    if rows.isEmpty {
      Text(commands.isEmpty ? "No commands in the current scope." : "No matches.")
        .foregroundStyle(.separator)
        .padding(.vertical, 1)
    } else {
      VStack(alignment: .leading, spacing: 0) {
        ForEach(0..<rows.count, id: \.self) { index in
          row(for: rows[index].command)
        }
      }
    }
  }

  private func row(for command: ActivePaletteCommand) -> some View {
    Button {
      command.action()
      dismiss()
    } label: {
      HStack(spacing: 2) {
        Text(command.name)
        if let description = command.description {
          Spacer()
          Text(description).foregroundStyle(.separator)
        }
      }
    }
    .disabled(!command.isEnabled)
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
