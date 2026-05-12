import SwiftTUI
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct PopoverTabTests {
  @Test("PopoverTab resolves and rasterises anchored popover surfaces")
  func rendersPopoverShowcase() {
    let terminalSize = CellSize(width: 80, height: 30)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      PopoverTab(),
      context: .init(
        identity: Identity(components: [.named("PopoverTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Popovers"))
    #expect(surface.contains("Boolean binding"))
    #expect(surface.contains("Details popover"))
    #expect(surface.contains("Optional item binding"))
    #expect(surface.contains("TipKit-inspired tip"))
  }

  @Test("Gallery initial-tab aliases select the popovers tab")
  func galleryInitialTabAliasesIncludePopovers() {
    #expect(GalleryView.GalleryTab(environmentName: "popover") == .popovers)
    #expect(GalleryView.GalleryTab(environmentName: "popovers") == .popovers)
    #expect(GalleryView.GalleryTab(environmentName: "tips") == .popovers)
  }
}
