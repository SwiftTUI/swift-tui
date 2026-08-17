@_spi(Runners) import SwiftTUIRuntime
import Testing

@testable import SwiftTUICLIAttach
@testable import SwiftTUITerminalCLI

@Suite
@MainActor
struct SceneInfoRegistryTests {
  @Test("Scene info registry reflects attachment changes")
  func reflectsAttachmentChanges() throws {
    struct TwoSceneApp: App {
      var body: some Scene {
        WindowGroup("Primary", id: WindowIdentifier("primary")) {
          EmptyView()
        }
        WindowGroup("Secondary", id: WindowIdentifier("secondary")) {
          EmptyView()
        }
      }
    }
    let selections = collectWindowSceneSelections(from: TwoSceneApp().body)

    let primary = try SceneRuntime(selection: selections[0], isPrimary: true)
    let secondary = try SceneRuntime(selection: selections[1], isPrimary: false)
    // The same runtime → entry mapping TerminalRunner.launchApp performs.
    let registry = SceneInfoRegistry(
      entries: [primary, secondary].map { runtime in
        .init(
          id: runtime.selection.identifier.rawValue,
          title: runtime.selection.title,
          ptyPath: runtime.attachPtyPath,
          isPrimary: runtime.isPrimary
        )
      }
    )

    let initial = registry.scenes()
    #expect(initial.first(where: { $0.id == "primary" })?.isAttached == true)
    #expect(initial.first(where: { $0.id == "secondary" })?.isAttached == false)

    registry.markAttached(sceneID: "secondary")
    let attached = registry.scenes()
    #expect(attached.first(where: { $0.id == "secondary" })?.isAttached == true)

    registry.markDetached(sceneID: "secondary")
    let detached = registry.scenes()
    #expect(detached.first(where: { $0.id == "secondary" })?.isAttached == false)

    primary.shutdown()
    secondary.shutdown()
  }
}
