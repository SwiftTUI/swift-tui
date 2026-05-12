import CoreGraphics
import SwiftTUI
import Testing

@testable import SwiftUIHost

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

  try await waitUntil("semantic snapshot") {
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

  try await waitUntil("visible semantic snapshot") {
    host.latestSemanticSnapshot?.accessibilityNodes.contains {
      $0.label == "Visible action"
    } == true
  }

  let labels = host.latestSemanticSnapshot?.accessibilityNodes.compactMap(\.label) ?? []
  #expect(labels.contains("Visible action"))
  #expect(!labels.contains("Hidden action"))
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

@MainActor
private func waitUntil(
  _ label: String,
  timeoutNanoseconds: UInt64 = 2_000_000_000,
  pollNanoseconds: UInt64 = 5_000_000,
  condition: @escaping () async -> Bool
) async throws {
  let clock = ContinuousClock()
  let start = clock.now

  while !(await condition()) {
    if start.duration(to: clock.now) >= .nanoseconds(Int64(timeoutNanoseconds)) {
      throw SwiftUIHostAccessibilityTestTimeout(label)
    }
    try await Task.sleep(nanoseconds: pollNanoseconds)
  }
}

private struct SwiftUIHostAccessibilityTestTimeout: Error, CustomStringConvertible {
  let label: String

  init(_ label: String) {
    self.label = label
  }

  var description: String {
    "Timed out waiting for \(label)"
  }
}

extension RasterSurface {
  fileprivate var renderedText: String {
    lines.joined(separator: "\n")
  }
}
