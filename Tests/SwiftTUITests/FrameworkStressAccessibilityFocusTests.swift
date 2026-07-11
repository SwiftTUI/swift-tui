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

// MARK: - Attempt 002: explicit-to-inferred label replacement

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 002 removing explicit label clears retained metadata")
  func stress002RemovingExplicitLabelClearsRetainedMetadata() throws {
    // Hypothesis: a same-identity branch replacement can leave explicit accessibility metadata
    // attached after the replacement returns to the control's inferred visible label.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF002", "Root"),
      size: .init(width: 62, height: 8)
    ) {
      StressAF002Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<5 {
      _ = try harness.clickText("Advance explicit label")
    }
    _ = try harness.clickText("Use inferred label")

    let target = try #require(
      accessibilityFocusNodes(in: harness).last { $0.role == .button }
    )
    #expect(target.role == .button)
    #expect(target.label == nil)
    #expect(!accessibilityFocusNodes(in: harness).contains { $0.label == "Explicit target 5" })
  }
}

@MainActor
private struct StressAF002Fixture: View {
  @State private var generation = 0
  @State private var usesExplicitLabel = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance explicit label") {
        generation += 1
      }
      Button("Use inferred label") {
        usesExplicitLabel = false
      }
      if usesExplicitLabel {
        Button("Visible target \(generation)") {}
          .id("stress-af-002-target")
          .accessibilityLabel("Explicit target \(generation)")
      } else {
        Button("Visible target \(generation)") {}
          .id("stress-af-002-target")
      }
    }
  }
}
