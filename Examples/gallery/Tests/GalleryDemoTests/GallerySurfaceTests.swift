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
    #expect(surface.contains("Component Gallery"))
    #expect(surface.contains("Controls"))
    #expect(surface.contains("Arrow"))
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
}
