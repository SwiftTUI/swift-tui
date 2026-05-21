import SwiftTUI
import SwiftTUIAnimatedImage
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct ImagesTabAnimatedGIFTests {
  @Test("embedded gallery GIF decodes into a multi-frame animated image sequence")
  func embeddedGIFDecodes() throws {
    let sequence = try AnimatedGIF.decode(data: ImagesTab.gifBytes)

    #expect(sequence.frames.count > 1)
    #expect(sequence.frameDelays.count == sequence.frames.count)
  }

  @Test("ImagesTab resolves and rasterises the animated GIF preview surface")
  func rendersAnimatedImageShowcase() {
    let terminalSize = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      ImagesTab(),
      context: .init(
        identity: Identity(components: [.named("ImagesTabAnimatedGIFSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Images"))
    #expect(surface.contains("Animated GIF"))
    #expect(surface.contains("Nyan fixture"))
    #expect(!surface.contains("GIF (frame 0)"))
  }

  @Test("Gallery initial-tab aliases select Images for animated GIF coverage")
  func galleryInitialTabAliasesSelectImagesForAnimatedGIFCoverage() throws {
    #expect(GalleryView.GalleryTab(environmentName: "gif") == .images)
    #expect(GalleryView.GalleryTab(environmentName: "animated-gif") == .images)
    #expect(GalleryView.GalleryTab(environmentName: "animated-image") == .images)
  }
}
