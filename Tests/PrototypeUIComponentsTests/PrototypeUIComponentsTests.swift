import PrototypeUIComponents
import TerminalUI
import Testing

@MainActor
@Suite
struct PrototypeUIComponentsTests {
  @Test("command catalog ranks title matches ahead of keyword matches")
  func commandCatalogRanksTitleMatchesAheadOfKeywordMatches() {
    let catalog = PrototypeCommandCatalog(
      [
        PrototypeCommand(
          id: "keyword-only",
          title: "Archive thread",
          keywords: ["help"]
        ),
        PrototypeCommand(
          id: "title-contained",
          title: "Open help",
          keywords: ["guide"]
        ),
        PrototypeCommand(
          id: "title-prefix",
          title: "Help center",
          keywords: ["support"]
        ),
      ]
    )

    #expect(
      catalog.matching("help").map(\.id) == [
        "title-prefix",
        "title-contained",
        "keyword-only",
      ]
    )
  }

  @Test("help surface renders compact key bindings")
  func helpSurfaceRendersCompactKeyBindings() {
    let surface = renderedText(
      PrototypeHelpSurface(
        [
          PrototypeKeyBindingGroup(
            "Global",
            bindings: [
              PrototypeKeyBinding("?", "Help"),
              PrototypeKeyBinding("q", "Quit"),
            ]
          ),
          PrototypeKeyBindingGroup(
            "Palette",
            bindings: [
              PrototypeKeyBinding("/", "Search")
            ]
          ),
        ]
      )
    )

    #expect(surface.contains("Global"))
    #expect(surface.contains("[?]"))
    #expect(surface.contains("Help"))
    #expect(surface.contains("[q]"))
    #expect(surface.contains("Palette"))
    #expect(surface.contains("[/]"))
    #expect(surface.contains("Search"))
  }

  @Test("command palette filters results and shows an empty state")
  func commandPaletteFiltersResultsAndShowsEmptyState() {
    let matchingSurface = renderedText(
      PrototypeCommandPalette(
        query: .constant("open"),
        commands: [
          PrototypeCommand(
            id: "open-file",
            title: "Open file",
            detail: "Browse local files",
            keywords: ["files", "picker"],
            shortcut: "o"
          ),
          PrototypeCommand(
            id: "quit",
            title: "Quit",
            detail: "Close the app",
            keywords: ["exit", "close"],
            shortcut: "q"
          ),
        ]
      )
    )

    #expect(matchingSurface.contains("Open file"))
    #expect(matchingSurface.contains("Browse local files"))
    #expect(!matchingSurface.contains("Quit"))

    let emptySurface = renderedText(
      PrototypeCommandPalette(
        query: .constant("zebra"),
        commands: [
          PrototypeCommand(
            id: "open-file",
            title: "Open file",
            detail: "Browse local files",
            keywords: ["files", "picker"],
            shortcut: "o"
          )
        ],
        emptyState: "No commands found"
      )
    )

    #expect(emptySurface.contains("No commands found"))
  }
}

@MainActor
private func renderedText<V: View>(
  _ view: V
) -> String {
  let artifacts = DefaultRenderer().render(
    view,
    context: .init(identity: .init(components: ["PrototypeSurface"]))
  )
  return artifacts.rasterSurface.lines.joined(separator: "\n")
}
