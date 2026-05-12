import SwiftTUI

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
/// `.toolbar(style:)` absorbs toolbar items).
struct CommandPaletteList: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  var body: some View {
    Group {
      CommandPaletteListBody(
        commands: commands,
        dismiss: dismiss
      )
    }
  }
}

private struct CommandPaletteListBody: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  @State private var query = ""
  @FocusState private var isQueryFocused: Bool

  private var matches: [(command: ActivePaletteCommand, score: Int)] {
    if query.isEmpty {
      return commands.enumerated().map { ($0.element, $0.offset) }
    }
    return
      commands
      .compactMap { command in
        fuzzyMatchScore(query: query, against: command.name)
          .map { (command: command, score: $0) }
      }
      .sorted { $0.score < $1.score }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Divider()
      diagnosticRow
      TextField("Filter commands…", text: $query)
        .focused($isQueryFocused)
      Divider()
      matchList
      Divider()
      footer
    }
    .padding(1)
    .frame(minWidth: 44, alignment: .leading)
    .onAppear {
      query = ""
      isQueryFocused = true
    }
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
      Text("focus=\(isQueryFocused ? "yes" : "no")")
      Spacer()
    }
    .foregroundStyle(.separator)
  }

  // Footer with an explicit Close button. The framework's Esc-closes-
  // presentation behavior was removed in Phase 0 of the ActionScopes
  // rewrite and has not yet been reinstated (see
  // Tests/SwiftTUITests/AppRuntimeTests.swift:225 — "Escape-owned
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
