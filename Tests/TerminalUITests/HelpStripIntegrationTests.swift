import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
@testable import View

@MainActor
@Suite
struct HelpStripIntegrationTests {
  @Test("view-level .help renders Save title and key glyph in the raster")
  func viewLevelHelpRendersSaveToken() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s")
        ) {}
        .help(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 5)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Save"))
    #expect(surface.contains("[^S]"))
  }

  @Test("scene-level command surfaces in the view-level help strip")
  func sceneLevelCommandSurfacesInHelpStrip() throws {
    let scene = WindowGroup(id: "primary") {
      Text("Body")
        .help()
    }
    .commands {
      CommandItem(id: "quit", title: "Quit", key: .ctrl("q"), group: "Session") {}
    }

    let artifacts = try render(scene)
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Quit"))
    #expect(surface.contains("[^Q]"))
  }

  @Test("mixed scene-level and view-level commands both appear in the strip")
  func mixedSceneAndViewLevelAppearInStrip() throws {
    let scene = WindowGroup(id: "primary") {
      Text("Body")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s")
        ) {}
        .help()
    }
    .commands {
      CommandItem(id: "quit", title: "Quit", key: .ctrl("q")) {}
    }

    let artifacts = try render(scene)
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    #expect(surface.contains("Save"))
    #expect(surface.contains("[^S]"))
    #expect(surface.contains("Quit"))
    #expect(surface.contains("[^Q]"))
  }

  @Test("help strip coexists with command palette without z-order conflicts")
  func helpStripCoexistsWithCommandPalette() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s")
        ) {}
        .help()
        .commandPalette(isPresented: .constant(true)),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 60, height: 12)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")

    // Command palette overlay still appears.
    #expect(surface.contains("Command Palette"))
    // Help strip title still renders somewhere in the tree.
    // (The overlay may draw over some cells, but both systems remain
    // functional — we're checking that the strip didn't throw or
    // break the palette.)
    #expect(surface.contains("Save"))
  }
}

// MARK: - Helpers

@MainActor
private func render<S: Scene>(
  _ scene: S,
  width: Int = 40,
  height: Int = 5
) throws -> FrameArtifacts {
  var visitor = HelpStripSceneCaptureVisitor(
    proposal: .init(width: width, height: height)
  )
  let artifacts = try #require(
    withFirstWindowSceneConfiguration(
      in: scene,
      visitor: &visitor
    )
  )
  return artifacts
}

@MainActor
private struct HelpStripSceneCaptureVisitor: WindowSceneConfigurationVisitor {
  let proposal: ProposedSize

  mutating func visit<Content: View>(
    descriptor _: TerminalUISceneDescriptor,
    configuration: WindowSceneConfiguration<Content>
  ) -> WindowSceneConfigurationVisitResult<FrameArtifacts> {
    let context = ResolveContext(identity: configuration.rootIdentity)
    let artifacts = DefaultRenderer().render(
      configuration.makeScopedRootView(),
      context: context,
      proposal: proposal
    )
    return .finish(artifacts)
  }
}
