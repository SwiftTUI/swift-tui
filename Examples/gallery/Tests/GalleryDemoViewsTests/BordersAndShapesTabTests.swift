import TerminalUI
import Testing

@testable import GalleryDemoViews

// Smoke test for the Borders & Shapes demo tab.
//
// The tab is gallery demo code, not library code, so the bar is
// deliberately low: we just want to catch a future edit that causes
// the tab to stop compiling or stop producing cells. Rendering the
// full tab through `DefaultRenderer` and asserting a non-empty raster
// surface gives us that regression guard without coupling to any
// particular glyph layout.
@MainActor
@Suite
struct BordersAndShapesTabTests {
  @Test("BordersAndShapesTab resolves and rasterises to a non-empty surface")
  func rendersNonEmptySurface() {
    let terminalSize = Size(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      BordersAndShapesTab(),
      context: .init(
        identity: Identity(components: [.named("BordersAndShapesTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    // Non-zero cell count proves the tab compiled, resolved, and
    // produced a non-empty raster surface.
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(artifacts.rasterSurface.lines.contains { !$0.isEmpty })
  }
}
