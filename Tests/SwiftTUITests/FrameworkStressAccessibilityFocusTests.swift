import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI accessibility and focus stress behavior", .serialized)
struct FrameworkStressAccessibilityFocusTests {}

@MainActor
private func accessibilityFocusNodes<Content: View>(
  in harness: StressRuntimeHarness<Content>
) -> [AccessibilityNode] {
  harness.runLoop.latestSemanticSnapshot.accessibilityNodes
}

// MARK: - Attempt 001: retained accessibility hint refresh

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 001 retained hint tracks repeated state churn")
  func stress001RetainedHintTracksRepeatedStateChurn() throws {
    // Hypothesis: semantic extraction can preserve a stable control's first accessibility hint
    // after repeated state-only invalidations leave its identity and geometry unchanged.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF001", "Root"),
      size: .init(width: 56, height: 8)
    ) {
      StressAF001Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<12 {
      _ = try harness.clickText("Advance hint")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Hint target" }
    )
    #expect(target.hint == "Performs generation 12")
    #expect(!accessibilityFocusNodes(in: harness).contains { $0.hint == "Performs generation 0" })
  }
}

@MainActor
private struct StressAF001Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance hint") {
        generation += 1
      }
      Button("Hint target") {}
        .id("stress-af-001-target")
        .accessibilityLabel("Hint target")
        .accessibilityHint("Performs generation \(generation)")
    }
  }
}
