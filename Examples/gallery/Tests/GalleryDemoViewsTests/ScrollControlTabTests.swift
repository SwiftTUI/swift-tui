import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct ScrollControlTabTests {
  @Test("ScrollControlTab resolves and rasterises proxy examples")
  func rendersScrollControlShowcase() {
    let terminalSize = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      ScrollControlTab(),
      context: .init(
        identity: Identity(components: [.named("ScrollControlTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Scroll Control"))
    #expect(surface.contains("ScrollViewReader drives identity"))
    #expect(surface.contains("Top"))
    #expect(surface.contains("Errors"))
  }

  @Test("Gallery initial-tab aliases select the scroll control tab")
  func galleryInitialTabAliasesIncludeScrollControl() {
    #expect(GalleryView.GalleryTab(environmentName: "scroll") == .scrollControl)
    #expect(GalleryView.GalleryTab(environmentName: "scroll-control") == .scrollControl)
    #expect(GalleryView.GalleryTab(environmentName: "scrolling") == .scrollControl)
  }
}
