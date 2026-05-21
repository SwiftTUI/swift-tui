import ArgumentParser
import SwiftTUI

struct DagCommand: AsyncParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "dag",
    abstract: "git log --graph style DAG (last N commits)."
  )

  @OptionGroup var opts: GitVizOptions

  @Option(name: .long, help: "Maximum number of commits to lay out.")
  var max: Int = 200

  @MainActor func run() async throws {
    let repo = try GitRepo(workingDirectory: opts.resolvedPath)
    let layout = try repo.revList(max: max)

    let bailFooter =
      layout.bailed
      ? "(stopped — exceeded maximum lane count)" : nil

    GitVizRunOnce.print(
      VStack(alignment: .leading, spacing: 0) {
        Text("DAG (last \(layout.commits.count) commits, newest first)").bold()
        Divider()
        ForEach(layout.commits, id: \.sha) { commit in
          HStack(spacing: 1) {
            GraphGlyphsRow(glyphs: commit.glyphs)
            Text(commit.sha.prefix(7).description).foregroundStyle(.muted)
            Text(commit.subject)
          }
          if let connector = commit.connectorGlyphs {
            GraphGlyphsRow(glyphs: connector)
          }
        }
        if let bailFooter {
          Divider()
          Text(bailFooter).foregroundStyle(.muted)
        }
      },
      opts: opts
    )
  }
}

/// Renders a row of `GraphGlyph`s with per-glyph lane coloring. Each
/// glyph becomes its own `Text` so the lane-color palette applies
/// independently — matching the same pattern `LineChart` uses for its
/// per-cell tone styling.
private struct GraphGlyphsRow: View {
  let glyphs: [GraphGlyph]

  var body: some View {
    HStack(spacing: 0) {
      ForEach(glyphs.indices, id: \.self) { index in
        Text(String(glyphs[index].character))
          .foregroundStyle(LanePalette.style(for: glyphs[index].lane))
      }
    }
  }
}
