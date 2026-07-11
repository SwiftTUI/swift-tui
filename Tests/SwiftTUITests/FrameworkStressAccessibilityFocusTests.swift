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

// MARK: - Attempt 003: explicit accessibility role removal

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 003 removed role does not survive branch churn")
  func stress003RemovedRoleDoesNotSurviveBranchChurn() throws {
    // Hypothesis: stable explicit identity can cause retained semantic metadata to preserve a
    // departed heading role when a conditional branch returns to label-only group semantics.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF003", "Root"),
      size: .init(width: 48, height: 7)
    ) {
      StressAF003Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<9 {
      _ = try harness.clickText("Toggle target role")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Role target" }
    )
    #expect(target.role == .group)
    #expect(
      !accessibilityFocusNodes(in: harness).contains {
        $0.label == "Role target" && $0.role == .heading(level: 2)
      })
  }
}

@MainActor
private struct StressAF003Fixture: View {
  @State private var usesHeading = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle target role") {
        usesHeading.toggle()
      }
      if usesHeading {
        Text("Stable visible text")
          .id("stress-af-003-target")
          .accessibilityRole(.heading(level: 2))
          .accessibilityLabel("Role target")
      } else {
        Text("Stable visible text")
          .id("stress-af-003-target")
          .accessibilityLabel("Role target")
      }
    }
  }
}

// MARK: - Attempt 004: accessibility metadata tuple coherence

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 004 label hint and role update atomically")
  func stress004LabelHintAndRoleUpdateAtomically() throws {
    // Hypothesis: retained semantic synchronization can mix fields from adjacent generations
    // when label, hint, and role all change without an identity or geometry change.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF004", "Root"),
      size: .init(width: 52, height: 7)
    ) {
      StressAF004Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<11 {
      _ = try harness.clickText("Advance metadata tuple")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Control 11" }
    )
    #expect(target.hint == "Hint 11")
    #expect(target.role == .link)
    #expect(
      !accessibilityFocusNodes(in: harness).contains {
        $0.label?.hasPrefix("Control ") == true && $0.label != "Control 11"
      })
  }
}

@MainActor
private struct StressAF004Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance metadata tuple") {
        generation += 1
      }
      Text("Stable target")
        .id("stress-af-004-target")
        .accessibilityRole(generation.isMultiple(of: 2) ? .button : .link)
        .accessibilityLabel("Control \(generation)")
        .accessibilityHint("Hint \(generation)")
    }
  }
}
