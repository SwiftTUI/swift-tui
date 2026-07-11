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

// MARK: - Attempt 009: duplicate exact semantic identity isolation

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 009 duplicate exact identities keep current semantics")
  func stress009DuplicateExactIdentitiesKeepCurrentSemantics() throws {
    // Hypothesis: semantic extraction keyed by Identity can collapse or cross-wire two live nodes
    // that intentionally share an exact identity while their order and metadata swap repeatedly.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF009", "Root"),
      size: .init(width: 54, height: 8)
    ) {
      StressAF009Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<9 {
      _ = try harness.clickText("Swap duplicate semantics")
    }

    let duplicates = accessibilityFocusNodes(in: harness).filter {
      $0.label?.hasPrefix("Duplicate owner") == true
    }
    #expect(duplicates.map(\.label) == ["Duplicate owner B 9", "Duplicate owner A 9"])
    #expect(duplicates.map(\.role) == [.link, .button])
  }
}

@MainActor
private struct StressAF009Fixture: View {
  static let duplicateIdentity = testIdentity("StressAF009", "Duplicate")

  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Swap duplicate semantics") {
        generation += 1
      }
      if generation.isMultiple(of: 2) {
        target("A", role: .button)
        target("B", role: .link)
      } else {
        target("B", role: .link)
        target("A", role: .button)
      }
    }
  }

  private func target(_ owner: String, role: AccessibilityRole) -> some View {
    Text("Duplicate visible \(owner)")
      .id(Self.duplicateIdentity)
      .accessibilityRole(role)
      .accessibilityLabel("Duplicate owner \(owner) \(generation)")
  }
}

// MARK: - Attempt 010: inferred accessibility label refresh

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 010 inferred heading label tracks draw payload churn")
  func stress010InferredHeadingLabelTracksDrawPayloadChurn() throws {
    // Hypothesis: accessibility label inference can read a retained heading's earlier draw payload
    // when only text content invalidates across many same-size generations.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF010", "Root"),
      size: .init(width: 52, height: 7)
    ) {
      StressAF010Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<15 {
      _ = try harness.clickText("Advance inferred heading")
    }

    let headings = accessibilityFocusNodes(in: harness).filter {
      $0.role == .heading(level: 3)
    }
    #expect(headings.map(\.label) == ["Heading payload 15"])
    #expect(!headings.contains { $0.label == "Heading payload 0" })
  }
}

@MainActor
private struct StressAF010Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance inferred heading") {
        generation += 1
      }
      Text("Heading payload \(generation)")
        .id("stress-af-010-heading")
        .accessibilityRole(.heading(level: 3))
    }
  }
}

// MARK: - Attempt 011: live-region policy churn

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 011 live region publishes current politeness")
  func stress011LiveRegionPublishesCurrentPoliteness() throws {
    // Hypothesis: a stable status node can retain its prior live-region policy when politeness and
    // label change together through off, polite, and assertive generations.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF011", "Root"),
      size: .init(width: 52, height: 7)
    ) {
      StressAF011Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<14 {
      _ = try harness.clickText("Cycle live policy")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Live status 14" }
    )
    #expect(target.role == .status)
    #expect(target.liveRegion == .assertive)
    #expect(!accessibilityFocusNodes(in: harness).contains { $0.label == "Live status 13" })
  }
}

@MainActor
private struct StressAF011Fixture: View {
  @State private var generation = 0

  private var politeness: AccessibilityPoliteness {
    switch generation % 3 {
    case 0: .off
    case 1: .polite
    default: .assertive
    }
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle live policy") {
        generation += 1
      }
      Text("Stable status")
        .id("stress-af-011-status")
        .accessibilityRole(.status)
        .accessibilityLabel("Live status \(generation)")
        .accessibilityLiveRegion(politeness)
    }
  }
}

// MARK: - Attempt 012: live-region modifier removal

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 012 removed live region policy leaves no residue")
  func stress012RemovedLiveRegionPolicyLeavesNoResidue() throws {
    // Hypothesis: same-identity conditional replacement can leave a departed live-region policy
    // on a status node that should return to ordinary, non-announcing semantics.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF012", "Root"),
      size: .init(width: 50, height: 7)
    ) {
      StressAF012Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<11 {
      _ = try harness.clickText("Toggle live modifier")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Optional live status" }
    )
    #expect(target.role == .status)
    #expect(target.liveRegion == nil)
  }
}

@MainActor
private struct StressAF012Fixture: View {
  @State private var isLive = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle live modifier") {
        isLive.toggle()
      }
      if isLive {
        status.accessibilityLiveRegion(.polite)
      } else {
        status
      }
    }
  }

  private var status: some View {
    Text("Stable optional status")
      .id("stress-af-012-status")
      .accessibilityRole(.status)
      .accessibilityLabel("Optional live status")
  }
}

// MARK: - Attempt 013: live-region duplicate identity isolation

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 013 live announcer isolates duplicate exact identities")
  func stress013LiveAnnouncerIsolatesDuplicateExactIdentities() throws {
    // Hypothesis: live-region baselines keyed only by public Identity can collapse two live status
    // nodes with the same exact identity and suppress or misattribute one owner's update.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF013", "Root"),
      size: .init(width: 54, height: 8)
    ) {
      StressAF013Fixture()
    }
    defer { harness.shutdown() }

    var announcer = LiveRegionAnnouncer()
    #expect(announcer.announcements(for: harness.runLoop.latestSemanticSnapshot).isEmpty)

    var latest: [LiveRegionAnnouncement] = []
    for _ in 0..<8 {
      _ = try harness.clickText("Advance duplicate live regions")
      latest = announcer.announcements(for: harness.runLoop.latestSemanticSnapshot)
    }

    #expect(latest.map(\.label) == ["Duplicate assertive 8", "Duplicate polite 8"])
    #expect(latest.map(\.politeness) == [.assertive, .polite])
  }
}

@MainActor
private struct StressAF013Fixture: View {
  static let duplicateIdentity = testIdentity("StressAF013", "DuplicateStatus")

  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance duplicate live regions") {
        generation += 1
      }
      Text("Polite visible \(generation)")
        .id(Self.duplicateIdentity)
        .accessibilityRole(.status)
        .accessibilityLabel("Duplicate polite \(generation)")
        .accessibilityLiveRegion(.polite)
      Text("Assertive visible \(generation)")
        .id(Self.duplicateIdentity)
        .accessibilityRole(.status)
        .accessibilityLabel("Duplicate assertive \(generation)")
        .accessibilityLiveRegion(.assertive)
    }
  }
}

// MARK: - Attempt 014: accessibility cursor anchor translation

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 014 cursor anchor follows local and layout movement")
  func stress014CursorAnchorFollowsLocalAndLayoutMovement() throws {
    // Hypothesis: retained semantic placement can apply either the previous local cursor anchor or
    // the previous global origin when both change on a stable accessibility node.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF014", "Root"),
      size: .init(width: 52, height: 7)
    ) {
      StressAF014Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<13 {
      _ = try harness.clickText("Move cursor anchor")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Moving cursor anchor" }
    )
    #expect(target.rect.origin.x == 3)
    #expect(
      target.cursorAnchor
        == CellPoint(x: target.rect.origin.x + 1, y: target.rect.origin.y))
  }
}

@MainActor
private struct StressAF014Fixture: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Move cursor anchor") {
        generation += 1
      }
      HStack(spacing: 0) {
        Spacer().frame(width: generation % 5)
        Text("Anchor target")
          .frame(width: 16, alignment: .leading)
          .id("stress-af-014-target")
          .accessibilityRole(.button)
          .accessibilityLabel("Moving cursor anchor")
          .accessibilityCursorAnchor(.init(x: generation % 4, y: 0))
      }
    }
  }
}

// MARK: - Attempt 015: accessibility cursor anchor removal

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 015 removed cursor anchor does not persist")
  func stress015RemovedCursorAnchorDoesNotPersist() throws {
    // Hypothesis: conditional same-identity replacement can retain an explicit cursor anchor after
    // the replacement returns to ordinary accessibility metadata.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF015", "Root"),
      size: .init(width: 48, height: 7)
    ) {
      StressAF015Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<11 {
      _ = try harness.clickText("Toggle cursor anchor")
    }

    let target = try #require(
      accessibilityFocusNodes(in: harness).first { $0.label == "Optional cursor target" }
    )
    #expect(target.cursorAnchor == nil)
  }
}

@MainActor
private struct StressAF015Fixture: View {
  @State private var hasAnchor = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle cursor anchor") {
        hasAnchor.toggle()
      }
      if hasAnchor {
        target.accessibilityCursorAnchor(.init(x: 4, y: 0))
      } else {
        target
      }
    }
  }

  private var target: some View {
    Text("Cursor target")
      .id("stress-af-015-target")
      .accessibilityRole(.button)
      .accessibilityLabel("Optional cursor target")
  }
}

// MARK: - Attempt 016: focus interaction capability churn

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 016 focus region publishes current interaction capability")
  func stress016FocusRegionPublishesCurrentInteractionCapability() throws {
    // Hypothesis: a stable focus region can retain its first activation/edit capability when only
    // FocusInteractions changes across otherwise geometry-identical renders.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF016", "Root"),
      size: .init(width: 52, height: 7)
    ) {
      StressAF016Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<13 {
      _ = try harness.clickText("Cycle focus capability")
    }

    let target = try #require(
      harness.runLoop.latestSemanticSnapshot.focusRegions.first {
        $0.identity == StressAF016Fixture.targetIdentity
      }
    )
    #expect(target.focusInteractions == .edit)
    #expect(
      harness.runLoop.latestSemanticSnapshot.focusRegions.filter {
        $0.identity == StressAF016Fixture.targetIdentity
      }.count == 1)
  }
}

@MainActor
private struct StressAF016Fixture: View {
  static let targetIdentity = testIdentity("StressAF016", "Target")

  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Cycle focus capability") {
        generation += 1
      }
      Text("Focus interaction target")
        .id(Self.targetIdentity)
        .focusable(
          true,
          interactions: generation.isMultiple(of: 2) ? .activate : .edit
        )
    }
  }
}

// MARK: - Attempt 017: focused target becomes nonfocusable

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 017 disabling focused target clears focus and region")
  func stress017DisablingFocusedTargetClearsFocusAndRegion() throws {
    // Hypothesis: a key-handler invalidation originating from the focused node can leave both the
    // tracker and retained semantic snapshot pointing at that node after it becomes nonfocusable.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF017", "Root"),
      size: .init(width: 44, height: 6)
    ) {
      StressAF017Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressAF017Fixture.targetIdentity)
    _ = try harness.pressKey(KeyPress(.character("r")))

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == nil)
    #expect(
      !harness.runLoop.latestSemanticSnapshot.focusRegions.contains {
        $0.identity == StressAF017Fixture.targetIdentity
      })
  }
}

@MainActor
private struct StressAF017Fixture: View {
  static let targetIdentity = testIdentity("StressAF017", "Target")

  @State private var isFocusable = true

  var body: some View {
    Text("Self-disabling focus target")
      .id(Self.targetIdentity)
      .focusable(isFocusable)
      .accessibilityLabel("Self-disabling focus target")
      .onKeyPress(.character("r")) { _ in
        isFocusable = false
        return .handled
      }
  }
}

// MARK: - Attempt 018: focused identity sibling reorder

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 018 stable focused identity survives sibling reorder")
  func stress018StableFocusedIdentitySurvivesSiblingReorder() throws {
    // Hypothesis: focus synchronization can preserve the old ordinal rather than the exact focused
    // identity when that identity moves across a stable focusable sibling repeatedly.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF018", "Root"),
      size: .init(width: 46, height: 7)
    ) {
      StressAF018Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressAF018Fixture.targetIdentity)
    for _ in 0..<11 {
      _ = try harness.pressKey(KeyPress(.character("r")))
    }

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressAF018Fixture.targetIdentity)
    let target = try #require(
      harness.runLoop.latestSemanticSnapshot.focusRegions.first {
        $0.identity == StressAF018Fixture.targetIdentity
      }
    )
    #expect(target.rect.origin.y == 1)
  }
}

@MainActor
private struct StressAF018Fixture: View {
  static let targetIdentity = testIdentity("StressAF018", "Target")
  static let peerIdentity = testIdentity("StressAF018", "Peer")

  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if reversed {
        peer
        target
      } else {
        target
        peer
      }
    }
  }

  private var target: some View {
    Text("Reordering focus target")
      .id(Self.targetIdentity)
      .focusable()
      .onKeyPress(.character("r")) { _ in
        reversed.toggle()
        return .handled
      }
  }

  private var peer: some View {
    Text("Stable focus peer")
      .id(Self.peerIdentity)
      .focusable()
  }
}

// MARK: - Attempt 019: focused target removal continuation

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 019 repeated focused removal chooses live continuation")
  func stress019RepeatedFocusedRemovalChoosesLiveContinuation() throws {
    // Hypothesis: focus tracker index repair can retain the removed middle target or drift to a
    // different ordinal after repeated focus-remove-reinsert cycles in one scope.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF019", "Root"),
      size: .init(width: 42, height: 8)
    ) {
      StressAF019Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<10 {
      _ = try harness.focus(StressAF019Fixture.middleIdentity)
      _ = try harness.pressKey(KeyPress(.character("r")))
      #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressAF019Fixture.firstIdentity)
      _ = try harness.pressKey(KeyPress(.character("a")))
    }

    #expect(
      harness.runLoop.latestSemanticSnapshot.focusRegions.map(\.identity) == [
        StressAF019Fixture.firstIdentity,
        StressAF019Fixture.middleIdentity,
        StressAF019Fixture.lastIdentity,
      ])
  }
}

@MainActor
private struct StressAF019Fixture: View {
  static let firstIdentity = testIdentity("StressAF019", "First")
  static let middleIdentity = testIdentity("StressAF019", "Middle")
  static let lastIdentity = testIdentity("StressAF019", "Last")

  @State private var showsMiddle = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("First continuation")
        .id(Self.firstIdentity)
        .focusable()
        .onKeyPress(.character("a")) { _ in
          showsMiddle = true
          return .handled
        }
      if showsMiddle {
        Text("Removable middle")
          .id(Self.middleIdentity)
          .focusable()
          .onKeyPress(.character("r")) { _ in
            showsMiddle = false
            return .handled
          }
      }
      Text("Last continuation")
        .id(Self.lastIdentity)
        .focusable()
    }
  }
}

// MARK: - Attempt 020: FocusState retarget during reorder

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 020 FocusState request follows reordered target")
  func stress020FocusStateRequestFollowsReorderedTarget() throws {
    // Hypothesis: a FocusState write issued in the same action as a sibling reorder can resolve
    // against the pre-reorder binding ordinal and focus the wrong live target.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF020", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      StressAF020Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<9 {
      _ = try harness.clickText("Retarget and reorder")
    }

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressAF020Fixture.secondIdentity)
    #expect(harness.frame.contains("FocusState value second"))
    #expect(harness.focusBindingRegistrationCount == 2)
  }
}

private enum StressAF020Field: Hashable {
  case first
  case second
}

@MainActor
private struct StressAF020Fixture: View {
  static let firstIdentity = testIdentity("StressAF020", "First")
  static let secondIdentity = testIdentity("StressAF020", "Second")

  @State private var reversed = false
  @FocusState private var focusedField: StressAF020Field?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("FocusState value \(focusLabel)")
      Button("Retarget and reorder") {
        reversed.toggle()
        focusedField = reversed ? .second : .first
      }
      if reversed {
        second
        first
      } else {
        first
        second
      }
    }
  }

  private var first: some View {
    Button("First FocusState target") {}
      .id(Self.firstIdentity)
      .focused($focusedField, equals: .first)
  }

  private var second: some View {
    Button("Second FocusState target") {}
      .id(Self.secondIdentity)
      .focused($focusedField, equals: .second)
  }

  private var focusLabel: String {
    switch focusedField {
    case .first: "first"
    case .second: "second"
    case nil: "none"
    }
  }
}

// MARK: - Attempt 021: preferred default focus does not reseed

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 021 default candidate does not steal user focus")
  func stress021DefaultCandidateDoesNotStealUserFocus() throws {
    // Hypothesis: repeated reevaluation of a preferred-default registration can reseed its
    // FocusState value and steal focus back from a user-selected peer in the same scope.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF021", "Root"),
      size: .init(width: 46, height: 8)
    ) {
      StressAF021Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressAF021Fixture.peerIdentity)
    for _ in 0..<12 {
      _ = try harness.pressKey(KeyPress(.character("u")))
    }

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressAF021Fixture.peerIdentity)
    #expect(harness.frame.contains("Default focus state peer 12"))
    #expect(harness.defaultFocusRegistrationCount == 2)
  }
}

private enum StressAF021Field: Hashable {
  case preferred
  case peer
}

@MainActor
private struct StressAF021Fixture: View {
  static let preferredIdentity = testIdentity("StressAF021", "Preferred")
  static let peerIdentity = testIdentity("StressAF021", "Peer")

  @Namespace private var namespace
  @FocusState private var focusedField: StressAF021Field?
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Default focus state \(focusLabel) \(generation)")
      Text("Preferred default target")
        .id(Self.preferredIdentity)
        .focusable()
        .focused($focusedField, equals: .preferred)
        .prefersDefaultFocus(in: namespace)
      Text("User-selected peer")
        .id(Self.peerIdentity)
        .focusable()
        .focused($focusedField, equals: .peer)
        .onKeyPress(.character("u")) { _ in
          generation += 1
          return .handled
        }
    }
    .focusScope(namespace)
  }

  private var focusLabel: String {
    switch focusedField {
    case .preferred: "preferred"
    case .peer: "peer"
    case nil: "none"
    }
  }
}

// MARK: - Attempt 022: focus-section traversal under reorder

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 022 tab escapes reordered focus section")
  func stress022TabEscapesReorderedFocusSection() throws {
    // Hypothesis: retained section metadata can follow the old structural ordinal when two focus
    // sections reorder, causing Tab to stop inside the current section instead of escaping it.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF022", "Root"),
      size: .init(width: 46, height: 9)
    ) {
      StressAF022Fixture()
    }
    defer { harness.shutdown() }

    for _ in 0..<10 {
      _ = try harness.focus(StressAF022Fixture.firstIdentity)
      _ = try harness.pressKey(KeyPress(.tab))
      #expect(
        harness.runLoop.focusTracker.currentFocusIdentity
          == StressAF022Fixture.outsideIdentity)
      _ = try harness.pressKey(KeyPress(.character("r")))
    }

    #expect(harness.focusRegionCount == 3)
  }
}

@MainActor
private struct StressAF022Fixture: View {
  static let firstIdentity = testIdentity("StressAF022", "Section", "First")
  static let secondIdentity = testIdentity("StressAF022", "Section", "Second")
  static let outsideIdentity = testIdentity("StressAF022", "Outside")

  @State private var reversed = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      if reversed {
        outside
        groupedSection
      } else {
        groupedSection
        outside
      }
    }
  }

  private var groupedSection: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Section first")
        .id(Self.firstIdentity)
        .focusable()
      Text("Section second")
        .id(Self.secondIdentity)
        .focusable()
    }
    .focusSection()
  }

  private var outside: some View {
    Text("Outside section")
      .id(Self.outsideIdentity)
      .focusable()
      .onKeyPress(.character("r")) { _ in
        reversed.toggle()
        return .handled
      }
  }
}

// MARK: - Attempt 023: focus-scope child replacement

extension FrameworkStressAccessibilityFocusTests {
  @Test("stress accessibility focus 023 replaced scope children reseat inside live scope")
  func stress023ReplacedScopeChildrenReseatInsideLiveScope() throws {
    // Hypothesis: focus replacement can lose the surviving scope path and fall back outside the
    // scope when every child identity is replaced by a focused child's own key action.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressAF023", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      StressAF023Fixture()
    }
    defer { harness.shutdown() }

    for generation in 0..<10 {
      _ = try harness.focus(StressAF023Fixture.firstIdentity(generation))
      _ = try harness.pressKey(KeyPress(.character("r")))
      #expect(
        harness.runLoop.focusTracker.currentFocusIdentity
          == StressAF023Fixture.firstIdentity(generation + 1))
    }

    #expect(harness.focusRegionCount == 3)
  }
}

@MainActor
private struct StressAF023Fixture: View {
  static let outerIdentity = testIdentity("StressAF023", "Outer")
  static let scopeIdentity = testIdentity("StressAF023", "Scope")

  static func firstIdentity(_ generation: Int) -> Identity {
    testIdentity("StressAF023", "First", "\(generation)")
  }

  static func secondIdentity(_ generation: Int) -> Identity {
    testIdentity("StressAF023", "Second", "\(generation)")
  }

  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Outer focus target")
        .id(Self.outerIdentity)
        .focusable()
      VStack(alignment: .leading, spacing: 0) {
        Text("Scoped first \(generation)")
          .id(Self.firstIdentity(generation))
          .focusable()
          .onKeyPress(.character("r")) { _ in
            generation += 1
            return .handled
          }
        Text("Scoped second \(generation)")
          .id(Self.secondIdentity(generation))
          .focusable()
      }
      .id(Self.scopeIdentity)
      .focusScope()
    }
  }
}
