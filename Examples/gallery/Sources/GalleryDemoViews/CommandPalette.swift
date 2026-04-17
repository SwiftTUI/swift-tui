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
struct CommandPaletteList: View {
  let commands: [ActivePaletteCommand]
  let dismiss: @MainActor @Sendable () -> Void

  @State private var query: String = ""

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
      TextField("Filter commands…", text: $query)
      Divider()
      matchList
    }
    .padding(1)
    .frame(minWidth: 44, alignment: .leading)
  }

  private var header: some View {
    HStack(spacing: 2) {
      Text("Command palette").bold()
      Spacer()
      Text("Tab + Enter to run · Esc to close")
        .foregroundStyle(.separator)
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
