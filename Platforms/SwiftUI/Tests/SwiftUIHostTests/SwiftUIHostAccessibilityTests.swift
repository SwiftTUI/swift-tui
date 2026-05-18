import CoreGraphics
import SwiftTUI
import SwiftTUITestSupport
import Testing

@testable import SwiftUIHost

@MainActor
@Suite(.serialized)
struct SwiftUIHostAccessibilityTests {
  @MainActor
  @Test
  func scene_host_stores_latest_semantic_snapshot() async throws {
    let host = try SwiftUIHostSceneHost(
      app: AccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )

    host.start()
    defer {
      host.stop()
    }

    try await waitUntil(
      "semantic snapshot",
      lastObservation: {
        host.latestSurface?.renderedText ?? "<no surface>"
      }
    ) {
      host.latestSurface?.renderedText.contains("Host") == true
        && host.latestSemanticSnapshot?.accessibilityNodes.contains {
          $0.label == "Host action"
        } == true
        && host.focusedAccessibilityIdentity != nil
    }

    let snapshot = try #require(host.latestSemanticSnapshot)
    let focusedIdentity = try #require(host.focusedAccessibilityIdentity)
    let actionNode = try #require(
      snapshot.accessibilityNodes.first {
        $0.label == "Host action"
      }
    )

    #expect(focusedIdentity == actionNode.identity)

    let overlay = HostedAccessibilityOverlay(
      semanticSnapshot: snapshot,
      focusedIdentity: focusedIdentity,
      cellSize: CGSize(width: 8, height: 16)
    )

    #expect(overlay.requestedNativeFocusID == focusedIdentity.path)
  }

  @MainActor
  @Test
  func scene_host_receives_snapshot_with_accessibility_hidden_subtrees_pruned() async throws {
    let host = try SwiftUIHostSceneHost(
      app: HiddenAccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )

    host.start()
    defer {
      host.stop()
    }

    try await waitUntil(
      "visible semantic snapshot",
      lastObservation: {
        let labels = host.latestSemanticSnapshot?.accessibilityNodes.compactMap(\.label) ?? []
        return "labels=\(labels)"
      }
    ) {
      host.latestSemanticSnapshot?.accessibilityNodes.contains {
        $0.label == "Visible action"
      } == true
    }

    let labels = host.latestSemanticSnapshot?.accessibilityNodes.compactMap(\.label) ?? []
    #expect(labels.contains("Visible action"))
    #expect(!labels.contains("Hidden action"))
  }

  @MainActor
  @Test
  func scene_host_drops_stale_semantic_host_frames() throws {
    let host = try SwiftUIHostSceneHost(
      app: AccessibilityHostApp(),
      descriptor: .init(id: "main", title: "Main", isDefault: true),
      style: .default
    )
    let root = Identity(components: ["root"])

    host.receiveFrameForTesting(
      SemanticHostFrame(
        sequence: 2,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["new"]),
        semantics: SemanticSnapshot(
          accessibilityNodes: [
            AccessibilityNode(
              identity: root.child("new"),
              parentIdentity: root,
              rect: .init(origin: .zero, size: .init(width: 3, height: 1)),
              role: .status,
              label: "new"
            )
          ]
        ),
        focusedIdentity: root.child("new")
      )
    )
    host.receiveFrameForTesting(
      SemanticHostFrame(
        sequence: 1,
        raster: RasterSurface(size: .init(width: 3, height: 1), lines: ["old"]),
        semantics: SemanticSnapshot(
          accessibilityNodes: [
            AccessibilityNode(
              identity: root.child("old"),
              parentIdentity: root,
              rect: .init(origin: .zero, size: .init(width: 3, height: 1)),
              role: .status,
              label: "old"
            )
          ]
        ),
        focusedIdentity: root.child("old")
      )
    )

    #expect(host.latestSurface?.renderedText.contains("new") == true)
    #expect(host.latestSemanticSnapshot?.accessibilityNodes.first?.label == "new")
    #expect(host.focusedAccessibilityIdentity == root.child("new"))
  }

}

@MainActor
private struct AccessibilityHostApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      Button("Host") {}
        .accessibilityLabel("Host action")
    }
  }
}

@MainActor
private struct HiddenAccessibilityHostApp: SwiftTUIRuntime.App {
  var body: some SwiftTUIRuntime.Scene {
    WindowGroup("Main", id: "main") {
      VStack(alignment: .leading, spacing: 0) {
        Button("Visible") {}
          .accessibilityLabel("Visible action")
        Button("Hidden") {}
          .accessibilityLabel("Hidden action")
          .accessibilityHidden()
      }
    }
  }
}

extension RasterSurface {
  fileprivate var renderedText: String {
    lines.joined(separator: "\n")
  }
}
