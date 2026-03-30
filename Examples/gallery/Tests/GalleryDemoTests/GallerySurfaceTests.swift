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

  @Test("Gallery color mode exposes named, semantic, and palette colors")
  func galleryShowsAvailableColors() {
    let model = GalleryDemoModel()
    model.activeTab = "appearance"
    model.selectedAppearanceDemo = "colors"
    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 96, height: 40, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryColorsRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Color Gallery"))
    #expect(surface.contains("Named colors"))
    #expect(surface.contains("Semantic roles"))
    #expect(surface.contains("Terminal palette"))
    #expect(surface.contains("magenta"))
    #expect(surface.contains("warning"))
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

  @Test("Gallery browser preview keeps the table metrics visible")
  func galleryBrowserPreviewKeepsTableMetricsVisible() {
    let model = GalleryDemoModel()
    model.activeTab = "collections"
    model.selectedCollectionDemo = "browser"

    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 96, height: 28, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryBrowserRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("List + Table"))
    #expect(surface.contains("Alpha"))
    #expect(surface.contains("Metric"))
    #expect(surface.contains("Latency"))
    #expect(surface.contains("Errors"))
  }

  @Test("Gallery palette preserves command details when filtered to one result")
  func galleryPalettePreservesCommandDetailsWhenFiltered() {
    let model = GalleryDemoModel()
    model.isPalettePresented = true
    model.paletteQuery = "reset"

    let artifacts = DefaultRenderer().render(
      GalleryDemoSceneView(model: model)
        .frame(width: 96, height: 24, alignment: .topLeading),
      context: .init(identity: testIdentity("GalleryPaletteFilteredRoot"))
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Reset Interactive Samples"))
    #expect(surface.contains("Restore the default gallery state"))
  }
}
