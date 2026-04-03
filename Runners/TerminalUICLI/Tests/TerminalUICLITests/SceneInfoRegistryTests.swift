@_spi(Runners) import TerminalUI
import Testing

@testable import TerminalUICLI

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
    let configurations = collectWindowSceneConfigurations(from: TwoSceneApp().body)

    let primary = try SceneRuntime(configuration: configurations[0], isPrimary: true)
    let secondary = try SceneRuntime(configuration: configurations[1], isPrimary: false)
    let registry = SceneInfoRegistry(runtimes: [primary, secondary])

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
