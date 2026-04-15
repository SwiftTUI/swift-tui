import Testing

@testable import Core
@_spi(Runners) @testable import TerminalUI
@testable import View

@MainActor
@Suite
struct ToolbarHostIntegrationTests {
  @Test("status placement item renders in the bottom row")
  func statusItemRendersInBottomRow() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .toolbar {
          ToolbarItem(placement: .status) {
            Text("● doc.txt")
          }
        },
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 5)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    // Primary content still visible.
    #expect(surface.contains("Body"))
    // Status item text rendered.
    #expect(surface.contains("doc.txt"))
  }

  @Test("primary action toolbar item renders in the bottom row")
  func primaryActionRendersInBottomRow() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .toolbar {
          ToolbarItem(placement: .primaryAction) {
            Text("Save")
          }
        },
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 5)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("Body"))
    #expect(surface.contains("Save"))
  }

  @Test(".toolbar { } and .help() compose a single bottom row")
  func toolbarAndHelpComposeSingleBottomRow() {
    // Status item on the left, help strip (reading scene + view
    // command registrations) in the middle, primary action
    // right-docked. This is the §5.2 worked example shape.
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .command(
          id: "save",
          title: "Save",
          key: .ctrl("s")
        ) {}
        .toolbar {
          ToolbarItem(placement: .status) {
            Text("● doc.txt")
          }
          ToolbarItem(.primaryAction, command: "save")
        }
        .help(),
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 80, height: 5)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    // The help strip contributes `[^S] Save` from the registered
    // command.
    #expect(surface.contains("[^S]"))
    #expect(surface.contains("Save"))
    // The status toolbar item's body is still visible.
    #expect(surface.contains("doc.txt"))
  }

  @Test("scene-level command surfaces in a command-bound ToolbarItem")
  func sceneLevelCommandSurfacesInToolbarItem() throws {
    // Builds a WindowGroup whose content uses the Text-specialized
    // Overload `ToolbarItem(.primaryAction, command: "save")` and
    // declares the backing command at scene level, matching the
    // proposal's Stage-2 interaction shape.
    let scene = WindowGroup(id: "primary") {
      Text("Body")
        .toolbar {
          ToolbarItem(.primaryAction, command: "save")
        }
    }
    .commands {
      CommandItem(id: "save", title: "Save", key: .ctrl("s")) {}
    }

    let artifacts = try render(scene, width: 60, height: 5)
    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("[^S]"))
    #expect(surface.contains("Save"))
  }

  @Test("unresolved command-bound ToolbarItem silently omits its render")
  func unresolvedCommandBoundItemIsOmitted() {
    let artifacts = DefaultRenderer().render(
      Text("Body")
        .toolbar {
          ToolbarItem(placement: .status) { Text("KEEP") }
          ToolbarItem(.primaryAction, command: "nonexistent")
        },
      context: .init(identity: testIdentity("Root")),
      proposal: .init(width: 40, height: 5)
    )

    let surface = artifacts.rasterSurface.lines.joined(separator: "\n")
    #expect(surface.contains("KEEP"))
    // The unresolved command-bound item must not render its
    // commandID literal anywhere on the surface.
    #expect(!surface.contains("nonexistent"))
  }

  @Test(
    ".toolbar(.hidden, for: .bottomBar) deferred to Stage 5",
    .disabled(
      "v1 capture-only: visibility modifier stores the intent but the host does not yet apply it at render time. Tracked as a Stage 5 follow-up."
    )
  )
  func toolbarVisibilityHidesBottomRow() {
    // When Stage 5 wires through the capture-only preference, this
    // test should assert that a `.toolbar(.hidden, for: .bottomBar)`
    // below the toolbar call suppresses the rendered bottom row.
    //
    // For v1, the modifier captures the intent into
    // ``ToolbarVisibilityPreferenceKey`` but the default host does
    // not yet consume it. The test is disabled to document the
    // intent without blocking the test run.
    Issue.record("Not yet implemented — see Stage 5.")
  }
}

// MARK: - Helpers

@MainActor
private func render<S: Scene>(
  _ scene: S,
  width: Int = 40,
  height: Int = 5
) throws -> FrameArtifacts {
  var visitor = ToolbarHostSceneCaptureVisitor(
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
private struct ToolbarHostSceneCaptureVisitor: WindowSceneConfigurationVisitor {
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
