import Testing

@testable import GalleryDemo
@testable import TerminalUI
@testable import TerminalUICharts

func testIdentity(_ components: String...) -> Identity {
  Identity(components: components)
}

@MainActor
@Suite
struct GallerySurfaceTests {
  @Test("Gallery launch explains non-terminal execution clearly")
  func galleryLaunchExplainsNonTerminalExecution() {
    let message = galleryLaunchFailureMessage(for: .notATTY(fileDescriptor: 0))

    #expect(message.contains("interactive terminal"))
    #expect(message.contains("Examples/gallery"))
  }

  @Test("Gallery renders a compact component atlas on a narrow short surface")
  func galleryRendersCompactAtlas() {
    let model = GalleryDemoModel()
    model.selectedControlDemo = "values"
    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 64, height: 24, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Gallery"))
    #expect(surface.contains("Controls"))
    #expect(surface.contains("Palette"))
    #expect(surface.contains("Buttons"))
    #expect(surface.contains("Inputs"))
    #expect(surface.contains("Value Controls"))
  }

  @Test("Gallery keeps its appearance samples visible in both color schemes")
  func galleryShowsBothAppearanceSamples() {
    let model = GalleryDemoModel()
    model.activeTab = "appearance"
    model.selectedAppearanceDemo = "accent"
    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 72, height: 24, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryThemeRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Preferred light mode"))
    #expect(surface.contains("Preferred dark mode"))
    #expect(surface.contains("Load"))
    #expect(surface.contains("Flag"))
  }

  @Test("Gallery value controls preview shows indeterminate progress")
  func galleryValueControlsPreviewShowsSyncProgress() {
    let model = GalleryDemoModel()
    model.selectedControlDemo = "values"
    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 96, height: 30, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryControlsRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Syncing"))
    #expect(surface.contains("Progress"))
  }

  @Test("Gallery palette renders a local searchable command overlay")
  func galleryPaletteRendersLocalCommandOverlay() {
    let model = GalleryDemoModel()
    model.isPalettePresented = true
    model.paletteQuery = "chart"

    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 80, height: 24, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryPaletteRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Command Palette"))
    #expect(surface.contains("Show Charts"))
    #expect(!surface.contains("Show Controls"))
  }
}
