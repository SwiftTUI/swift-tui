import Testing
import View

@testable import TerminalUI
@testable import TerminalUIScenes

@MainActor
@Suite
struct SceneManifestTests {
  private struct MultiSceneApp: App {
    var body: some Scene {
      WindowGroup("Dashboard", id: WindowIdentifier("dashboard")) {
        Text("Dashboard")
      }
      WindowGroup("Controls", id: WindowIdentifier("controls")) {
        Text("Controls")
      }
    }
  }

  @Test("scene manifest exposes descriptors in declaration order")
  func sceneManifestUsesDeclarationOrder() {
    let manifest = TerminalUISceneManifest(for: MultiSceneApp())

    #expect(manifest.defaultSceneID == WindowIdentifier("dashboard"))
    #expect(
      manifest.scenes == [
        .init(id: WindowIdentifier("dashboard"), title: "Dashboard", isDefault: true),
        .init(id: WindowIdentifier("controls"), title: "Controls", isDefault: false),
      ]
    )
  }

  @Test("scene manifest renders stable JSON")
  func sceneManifestRendersStableJSON() {
    let manifest = TerminalUISceneManifest(for: MultiSceneApp())

    #expect(
      manifest.jsonString
        == #"{"defaultSceneID":"dashboard","scenes":[{"id":"dashboard","title":"Dashboard","isDefault":true},{"id":"controls","title":"Controls","isDefault":false}]}"#
    )
  }
}
