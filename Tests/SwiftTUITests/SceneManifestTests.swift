import Foundation
import SwiftTUIViews
import Testing

@_spi(Runners) @testable import SwiftTUIRuntime

@MainActor
@Suite
struct SceneManifestTests {
  private struct CollidingTitlesApp: App {
    var body: some Scene {
      WindowGroup("Files / Recent") { Text("slash") }
      WindowGroup("Files - Recent") { Text("dash") }
    }
  }

  @Test("normalization collisions fail launch instead of choosing the first scene")
  func collidingTitlesCannotSelectTheWrongScene() throws {
    let app = CollidingTitlesApp()
    let manifest = SceneManifest(for: app)
    #expect(manifest.scenes[0].id == manifest.scenes[1].id)
    #expect(throws: AppLaunchError.duplicateSceneIdentifier(manifest.scenes[0].id)) {
      _ = try HostedSceneSession(
        for: app, sceneID: manifest.scenes[1].id,
        surface: HostedRasterSurface(
          surfaceSize: .init(width: 20, height: 4), appearance: .fallback, onFrame: { _ in }))
    }
  }

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
    let manifest = SceneManifest(for: MultiSceneApp())

    #expect(manifest.defaultSceneID == WindowIdentifier("dashboard"))
    #expect(
      manifest.scenes == [
        .init(id: WindowIdentifier("dashboard"), title: "Dashboard", isDefault: true),
        .init(id: WindowIdentifier("controls"), title: "Controls", isDefault: false),
      ]
    )
  }

  @Test func explicitSecondDefaultDerivesLegacyFlags() throws {
    let manifest = SceneManifest(
      defaultSceneID: "b",
      scenes: [
        .init(id: "a", title: nil, isDefault: true),
        .init(id: "b", title: nil, isDefault: false),
      ])
    #expect(manifest.scenes.map(\.isDefault) == [false, true])
    let json =
      try JSONSerialization.jsonObject(with: JSONEncoder().encode(manifest)) as? [String: Any]
    #expect(json?["defaultSceneId"] as? String == "b")
    for key in ["defaultSceneId", "defaultSceneID"] {
      let decoded = try JSONDecoder().decode(
        SceneManifest.self,
        from: Data(
          "{\"\(key)\":\"b\",\"scenes\":[{\"id\":\"a\",\"isDefault\":true},{\"id\":\"b\",\"title\":null}]}"
            .utf8))
      #expect(decoded.defaultSceneID == "b")
      #expect(decoded.scenes.map(\.isDefault) == [false, true])
    }
    #expect(
      try JSONDecoder().decode(SceneManifest.self, from: Data("[]".utf8)).defaultSceneID == nil)
  }

  @Test func ambiguousDecodedCatalogsFail() {
    for json in [
      #"{"defaultSceneId":"a","defaultSceneID":"b","scenes":[{"id":"a"},{"id":"b"}]}"#,
      #"{"defaultSceneId":"missing","scenes":[{"id":"a"}]}"#,
      #"[{"id":"a"},{"id":"a"}]"#,
      #"[{"id":"a","isDefault":true},{"id":"b","isDefault":true}]"#,
      #"[{"id":"a","isDefault":"false"}]"#,
    ] {
      #expect(throws: (any Error).self) {
        try JSONDecoder().decode(SceneManifest.self, from: Data(json.utf8))
      }
    }
  }

  @Test("scene manifest renders stable JSON")
  func sceneManifestRendersStableJSON() {
    let manifest = SceneManifest(for: MultiSceneApp())

    #expect(
      manifest.jsonString
        == #"{"defaultSceneID":"dashboard","scenes":[{"id":"dashboard","title":"Dashboard","isDefault":true},{"id":"controls","title":"Controls","isDefault":false}]}"#
    )
  }
}
