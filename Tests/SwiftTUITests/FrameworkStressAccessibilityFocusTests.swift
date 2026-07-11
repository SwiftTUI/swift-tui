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

// MARK: - Attempt 005: hidden ownership under semantic reorder

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 005 hidden state follows reordered semantic owner")
  func stress005HiddenStateFollowsReorderedSemanticOwner() throws {
    // Hypothesis: ordinal semantic reuse can attach accessibilityHidden to the old row when two
    // stable rows reverse order while the hidden owner changes in the same transaction.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF005", "Root"),
      size: .init(width: 52, height: 8)
    ) {
      StressAF005Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<9 {
      _ = try harness.clickText("Reorder hidden owner")
    }

    let labels = accessibilityFocusNodes(in: harness).compactMap(\.label)
    #expect(labels.contains("Semantic owner A generation 9"))
    #expect(!labels.contains("Semantic owner B generation 9"))
    #expect(!labels.contains { $0.contains("generation 8") })
  }
}

private struct StressAF005Row: Identifiable {
  let id: String
}

@MainActor
private struct StressAF005Fixture: View {
  @State private var generation = 0

  private var rows: [StressAF005Row] {
    let values = [StressAF005Row(id: "a"), StressAF005Row(id: "b")]
    return generation.isMultiple(of: 2) ? values : Array(values.reversed())
  }

  private var hiddenID: String {
    generation.isMultiple(of: 2) ? "a" : "b"
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder hidden owner") {
        generation += 1
      }
      ForEach(rows) { row in
        Text("Visible row \(row.id)")
          .accessibilityRole(.status)
          .accessibilityLabel("Semantic owner \(row.id.uppercased()) generation \(generation)")
          .accessibilityHidden(row.id == hiddenID)
      }
    }
  }
}

// MARK: - Attempt 006: hidden-descendant summary reset

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 006 ancestor hidden summary clears after descendant returns")
  func stress006AncestorHiddenSummaryClearsAfterDescendantReturns() throws {
    // Hypothesis: the retained accessibility subtree summary can keep an ancestor marked as
    // containing hidden content after the only hidden descendant returns with newer metadata.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF006", "Root"),
      size: .init(width: 58, height: 8)
    ) {
      StressAF006Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<10 {
      _ = try harness.clickText("Toggle nested hidden child")
    }

    let container = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Nested semantic container" }
    )
    #expect(!container.hidden)
    #expect(
      accessibilityFocusNodes(in: harness).contains {
        $0.label == "Nested child generation 10"
      })
    #expect(
      !accessibilityFocusNodes(in: harness).contains {
        $0.label == "Nested child generation 9"
      })
  }
}

@MainActor
private struct StressAF006Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle nested hidden child") {
        generation += 1
      }
      VStack(alignment: .leading, spacing: 0) {
        Text("Nested visible content")
          .accessibilityRole(.status)
          .accessibilityLabel("Nested child generation \(generation)")
          .accessibilityHidden(!generation.isMultiple(of: 2))
      }
      .id("stress-af-006-container")
      .accessibilityLabel("Nested semantic container")
    }
  }
}

// MARK: - Attempt 007: accessibility parent identity reparenting

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 007 reparented child references current semantic container")
  func stress007ReparentedChildReferencesCurrentSemanticContainer() throws {
    // Hypothesis: an explicitly identified child moving between semantic containers can retain
    // the departed parent's identity in the flattened accessibility hierarchy.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF007", "Root"),
      size: .init(width: 54, height: 8)
    ) {
      StressAF007Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<9 {
      _ = try harness.clickText("Move semantic child")
    }

    let nodes = accessibilityFocusNodes(in: harness)
    let currentParent = try #require(nodes.first { $0.label == "Container B" })
    let child = try #require(nodes.first { $0.label == "Reparented child 9" })
    #expect(child.parentIdentity == currentParent.identity)
    #expect(!nodes.contains { $0.label == "Container A" })
  }
}

@MainActor
private struct StressAF007Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Move semantic child") {
        generation += 1
      }
      if generation.isMultiple(of: 2) {
        semanticContainer("A")
      } else {
        semanticContainer("B")
      }
    }
  }

  private func semanticContainer(_ name: String) -> some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Child content")
        .id("stress-af-007-child")
        .accessibilityRole(.status)
        .accessibilityLabel("Reparented child \(generation)")
    }
    .id("stress-af-007-container-\(name)")
    .accessibilityRole(.region)
    .accessibilityLabel("Container \(name)")
  }
}

// MARK: - Attempt 008: accessibility reading order rotation

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 008 semantic reading order follows rotated collection")
  func stress008SemanticReadingOrderFollowsRotatedCollection() throws {
    // Hypothesis: retained ForEach placement can publish the previous accessibility reading order
    // after stable semantic owners rotate without changing their individual content geometry.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF008", "Root"),
      size: .init(width: 50, height: 9)
    ) {
      StressAF008Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<10 {
      _ = try harness.clickText("Rotate semantic rows")
    }

    let readingOrder = accessibilityFocusNodes(in: harness).compactMap(\.label).filter {
      $0.hasPrefix("Reading row")
    }
    #expect(readingOrder == ["Reading row B", "Reading row C", "Reading row A"])
  }
}

private struct StressAF008Row: Identifiable {
  let id: String
}

@MainActor
private struct StressAF008Fixture: View {
  @State private var generation = 0

  private var rows: [StressAF008Row] {
    switch generation % 3 {
    case 0:
      [StressAF008Row(id: "A"), StressAF008Row(id: "B"), StressAF008Row(id: "C")]
    case 1:
      [StressAF008Row(id: "B"), StressAF008Row(id: "C"), StressAF008Row(id: "A")]
    default:
      [StressAF008Row(id: "C"), StressAF008Row(id: "A"), StressAF008Row(id: "B")]
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Rotate semantic rows") {
        generation += 1
      }
      ForEach(rows) { row in
        Text("Stable row \(row.id)")
          .accessibilityRole(.cell)
          .accessibilityLabel("Reading row \(row.id)")
      }
    }
  }
}
