import SwiftTUI
import SwiftTUIAnimatedImage
import Testing

@testable import GalleryDemoViews

@MainActor
@Suite
struct AnimatedImageTabTests {
  @Test("embedded gallery GIF decodes into a multi-frame animated image sequence")
  func embeddedGIFDecodes() throws {
    let sequence = try AnimatedGIF.decode(data: ImagesTab.gifBytes)

    #expect(sequence.frames.count > 1)
    #expect(sequence.frameDelays.count == sequence.frames.count)
  }

  @Test("AnimatedImageTab resolves and rasterises its GIF preview surface")
  func rendersAnimatedImageShowcase() {
    let terminalSize = CellSize(width: 80, height: 28)
    var env = EnvironmentValues()
    env.terminalSize = terminalSize

    let artifacts = DefaultRenderer().render(
      AnimatedImageTab(),
      context: .init(
        identity: Identity(components: [.named("AnimatedImageTabSmoke")]),
        environmentValues: env
      ),
      proposal: .init(width: terminalSize.width, height: terminalSize.height)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(artifacts.rasterSurface.cells.count > 0)
    #expect(surface.contains("Animated GIF"))
    #expect(surface.contains("Nyan fixture"))
  }

  @Test("Gallery initial-tab aliases select the animated GIF tab")
  func galleryInitialTabAliasesIncludeAnimatedGIF() throws {
    #expect(GalleryView.GalleryTab(environmentName: "gif") == .animatedGIF)
    #expect(GalleryView.GalleryTab(environmentName: "animated-gif") == .animatedGIF)
    #expect(GalleryView.GalleryTab(environmentName: "animated-image") == .animatedGIF)
  }
}
