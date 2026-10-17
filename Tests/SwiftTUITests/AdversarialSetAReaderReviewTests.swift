@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAReaderReviewTests {
  @Test func setA901StaleSemanticFramesCannotChangeReviewOrEnqueueAnnouncements() {
    // Hypothesis: sequence rejection happens after mutating review or appending imperative notices.
    var reader = TerminalReaderModel()
    let live = node("Live")
    _ = reader.update(frame(5, [live]))
    let current = reader.current
    let stale = frame(4, [node("Stale")], announcements: [.init(message: "Obsolete notice")])
    #expect(reader.update(stale).isEmpty)
    #expect(reader.current == current)
    #expect(reader.currentChunk?.node.label == "Live")
    #expect(reader.takeUpdates().isEmpty)
  }

  @Test func setA902RepeatedAssistiveGenerationCannotUndoManualReviewNavigation() {
    // Hypothesis: every repaint replays an unchanged assistive focus request over operator navigation.
    var reader = TerminalReaderModel()
    let first = node("First")
    var second = node("Second")
    second.actionTarget = "second-target"
    var initial = frame(1, [first, second])
    initial.semantics.accessibilityFocusRequest = .init(generation: 7, target: "second-target")
    _ = reader.update(initial)
    #expect(reader.currentChunk?.node.label == "Second")
    _ = reader.navigate(-1)
    initial.sequence = 2
    #expect(reader.update(initial).isEmpty)
    #expect(reader.currentChunk?.node.label == "First")
  }

  @Test func setA903KeyboardTraversalCannotMoveTheIndependentReaderCursor() throws {
    // Hypothesis: committed keyboard focus is interpreted as an assistive-review focus request.
    let h = try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAReaderReview", "903"), size: .init(width: 40, height: 8)
    ) {
      VStack {
        Button("Keyboard first") {}
        Button("Keyboard second") {}
      }
    }
    defer { h.shutdown() }
    var reader = TerminalReaderModel()
    _ = reader.update(runtimeFrame(1, h))
    _ = reader.find("Keyboard second")
    let review = reader.current
    try h.focusText("Keyboard first")
    _ = reader.update(runtimeFrame(2, h))
    #expect(reader.current == review)
    #expect(reader.currentChunk?.node.label == "Keyboard second")
    try h.pressKey(.init(.tab))
    _ = reader.update(runtimeFrame(3, h))
    #expect(reader.current == review)
  }

  @Test func setA904StableActionOwnerSurvivesReportedIdentityReplacement() {
    // Hypothesis: review keys use mutable public node identity instead of the supplied action owner.
    var reader = TerminalReaderModel()
    var current = node("Original")
    current.actionIdentity = testIdentity("Stable action owner")
    _ = reader.update(frame(1, [node("Before"), current]))
    _ = reader.navigate(1)
    let identity = reader.current
    current.identity = testIdentity("Replacement public identity")
    current.label = "Updated payload"
    let notices = reader.update(frame(2, [node("Before"), current]))
    #expect(reader.current == identity)
    #expect(reader.currentChunk?.node.label == "Updated payload")
    #expect(!notices.joined().contains("removed"))
  }

  @Test func setA905DuplicatePublicIdentitiesKeepDistinctActionOwnersAcrossReorder() {
    // Hypothesis: duplicate-occurrence numbering overrides distinct action owners when rows reorder.
    var reader = TerminalReaderModel()
    var first = node("First owner")
    first.identity = testIdentity("Shared public identity")
    first.actionIdentity = testIdentity("Owner one")
    var second = node("Second owner")
    second.identity = first.identity
    second.actionIdentity = testIdentity("Owner two")
    _ = reader.update(frame(1, [first, second]))
    _ = reader.navigate(1)
    let review = reader.current
    _ = reader.update(frame(2, [second, first]))
    #expect(reader.current == review)
    #expect(reader.currentChunk?.node.label == "Second owner")
    #expect(reader.chunks.count == 2 && Set(reader.chunks.map(\.id)).count == 2)
  }

  @Test func setA906RemovedReviewTargetFallsBackAtItsPreviousOrdinal() {
    // Hypothesis: removing the current chunk always jumps to the first chunk instead of its successor.
    var reader = TerminalReaderModel()
    let first = node("First")
    let middle = node("Middle")
    let last = node("Last")
    _ = reader.update(frame(1, [first, middle, last]))
    _ = reader.navigate(1)
    let notices = reader.update(frame(2, [first, last]))
    #expect(reader.currentChunk?.node.label == "Last")
    #expect(notices.filter { $0.contains("Previous chunk removed") }.count == 1)
    #expect(reader.update(frame(3, [first, last])).isEmpty)
  }

  @Test func setA907TopmostModalBoundsSearchAndRestoresThePreviousReview() {
    // Hypothesis: review filtering admits an earlier sibling modal or loses the saved background cursor.
    var reader = TerminalReaderModel()
    let first = node("Background first")
    let last = node("Background last")
    _ = reader.update(frame(1, [first, last]))
    _ = reader.navigate(1)
    var lower = node("Lower modal", role: .sheet)
    lower.properties = .init(modal: true)
    var upper = node("Upper modal", role: .sheet)
    upper.properties = .init(modal: true)
    let child = node("Upper child", parent: upper.identity, role: .button)
    _ = reader.update(frame(2, [first, last, lower, upper, child]))
    #expect(reader.chunks.map(\.node.label) == ["Upper modal", "Upper child"])
    #expect(reader.find("Background").hasPrefix("No match"))
    #expect(reader.find("Lower modal").hasPrefix("No match"))
    _ = reader.update(frame(3, [first, last]))
    #expect(reader.currentChunk?.node.label == "Background last")
  }

  @Test func setA908UnnamedWrapperChainsKeepTheNearestMeaningfulParent() {
    // Hypothesis: pruning several transparent semantic groups stops ancestry repair after one edge.
    var reader = TerminalReaderModel()
    let parent = node("Named section", role: .heading(level: 2))
    var first = node("Wrapper one", parent: parent.identity)
    first.label = nil
    var second = node("Wrapper two", parent: first.identity)
    second.label = nil
    let leaf = node("Leaf", parent: second.identity, role: .button)
    _ = reader.update(frame(1, [parent, first, second, leaf]))
    #expect(reader.chunks.count == 2)
    #expect(reader.hierarchy(up: false).contains("Leaf"))
    #expect(reader.hierarchy(up: true).contains("Named section"))
  }

  @Test func setA909SectionReadingIncludesImmediateChildrenOnly() {
    // Hypothesis: section expansion recursively flattens grandchildren into their ancestor's chunk.
    var reader = TerminalReaderModel()
    let parent = node("Parent section")
    let child = node("Immediate child", parent: parent.identity)
    let grandchild = node("Deeper grandchild", parent: child.identity)
    _ = reader.update(frame(1, [parent, child, grandchild]))
    reader.sections = true
    let text = reader.read()
    #expect(text.contains("Immediate child"))
    #expect(!text.contains("Deeper grandchild"))
    #expect(reader.currentChunk?.node.identity == parent.identity)
  }

  @Test func setA910FindWrapsAfterCurrentWithoutRewritingEarlierHistory() {
    // Hypothesis: case-insensitive search stops at the end of review or includes the current node first.
    var reader = TerminalReaderModel()
    let first = node("Needle first")
    let other = node("Other")
    let last = node("NEEDLE last")
    _ = reader.update(frame(1, [first, other, last]))
    _ = reader.read()
    let initial = reader.history
    #expect(reader.find("needle").contains("NEEDLE last"))
    #expect(reader.find("NeEdLe").contains("Needle first"))
    #expect(Array(reader.history.prefix(initial.count)) == initial)
  }

  @Test func setA911AuthoredCategoryMatchingDoesNotAcceptAPartialName() {
    // Hypothesis: custom category navigation uses substring matching instead of exact case-folded names.
    var reader = TerminalReaderModel()
    var first = node("Database diagram")
    first.navigationCategories = ["Database"]
    var second = node("Data chart")
    second.navigationCategories = ["Data"]
    _ = reader.update(frame(1, [first, second]))
    #expect(reader.category("DATA").contains("Data chart"))
    let selected = reader.current
    #expect(reader.category("Dat").hasPrefix("No matching category"))
    #expect(reader.current == selected)
  }

  @Test func setA912TextPagingPreservesAnExtendedGraphemeAtThePageBoundary() {
    // Hypothesis: the 2048-character page slices UTF-8 scalars and splits a joined emoji cluster.
    var reader = TerminalReaderModel()
    let cluster = "👩🏽‍💻"
    var text = node("Long prose")
    text.control = .init(
      actions: [], value: .text(String(repeating: "a", count: 2047) + cluster + "Z"))
    _ = reader.update(frame(1, [text]))
    let first = reader.textPage(from: 0)
    #expect(first.contains(cluster + "\nCharacters 0 to 2048 of 2049."))
    #expect(!first.contains(cluster + "Z"))
    #expect(reader.textPage(from: 2048).hasPrefix("Z\nCharacters 2048 to 2049 of 2049."))
  }

  @Test func setA913ValueDescriptionCannotReplaceTheFullTextPagingSource() {
    // Hypothesis: human-readable summary override destroys access to a text control's full source value.
    var reader = TerminalReaderModel()
    var text = node("Code field", role: .textField)
    text.control = .init(actions: [], value: .text("let source = 42"))
    text.properties = .init(valueDescription: "One line of source code")
    _ = reader.update(frame(1, [text]))
    let summary = reader.read()
    #expect(summary.contains("One line of source code") && !summary.contains("let source = 42"))
    #expect(reader.textPage(from: 0).hasPrefix("let source = 42\n"))
  }

  @Test func setA914SelectionSummaryReplacesOpaqueValuesWithCurrentOptionLabels() {
    // Hypothesis: a retained selection summary displays its transport ID or an obsolete option label.
    var reader = TerminalReaderModel()
    var picker = node("Color choice", role: .picker)
    picker.control = .init(
      actions: [.setValue], value: .text("token-17"),
      selection: .init(
        presentation: .menu, options: [.init(id: "token-17", label: "Azure", isEnabled: true)]))
    _ = reader.update(frame(1, [picker]))
    #expect(reader.read().contains("Azure"))
    picker.control = .init(
      actions: [.setValue], value: .text("token-17"),
      selection: .init(
        presentation: .menu, options: [.init(id: "token-17", label: "Cobalt", isEnabled: true)]))
    _ = reader.update(frame(2, [picker]))
    let text = reader.read()
    #expect(text.contains("Cobalt") && !text.contains("Azure") && !text.contains("token-17"))
  }

  @Test func setA915ProtectedControlValuesCannotBeFoundThroughFullTextSearch() {
    // Hypothesis: secure summaries redact values but the separate full-text search path still indexes them.
    var reader = TerminalReaderModel()
    var secret = node("Password entry", role: .secureField)
    secret.control = .init(actions: [], value: .text("hidden-password-unique"))
    _ = reader.update(frame(1, [node("Public text"), secret]))
    #expect(reader.find("hidden-password-unique").hasPrefix("No match"))
    #expect(reader.find("Password entry").contains("Protected value"))
    #expect(reader.textPage(from: 0) == "Protected value.")
    #expect(!reader.history.joined().contains("hidden-password-unique"))
  }

  @Test func setA916PausedAnnouncePolicyRetainsUpdatesForExplicitReview() {
    // Hypothesis: pausing suppresses notices by draining and discarding their queued content.
    var reader = TerminalReaderCommands()
    _ = reader.model.update(frame(1, [node("Stable")]))
    _ = reader.command("policy announce")
    _ = reader.command("pause")
    let notices = reader.model.update(
      frame(2, [node("Stable")], announcements: [.init(message: "Queued while paused")]))
    #expect(notices.isEmpty)
    #expect(reader.model.pending.count == 1)
    _ = reader.command("resume")
    #expect(reader.model.pending.count == 1)
    #expect(reader.command("updates").output.contains("Queued while paused"))
    #expect(reader.command("updates").output == "No pending updates.")
  }

  @Test func setA917OffPolitenessNeverCreatesAPendingUpdateOrHistoryEntry() {
    // Hypothesis: an off announcement enters the update queue even though it should be suppressed.
    var reader = TerminalReaderModel()
    _ = reader.update(frame(1, [node("Stable")]))
    let notices = reader.update(
      frame(2, [node("Stable")], announcements: [.init(message: "Silent", politeness: .off)]))
    #expect(notices.isEmpty && reader.pending.isEmpty && reader.history.isEmpty)
    #expect(reader.takeUpdates().isEmpty)
  }

  @Test func setA918ProgressCompletionRetiresItsCoalescedIntermediateUpdate() {
    // Hypothesis: ordered completion is emitted while an older intermediate remains for the next drain.
    var reader = TerminalReaderModel()
    _ = reader.update(frame(1, [progress("Upload", value: 0)]))
    _ = reader.update(frame(2, [progress("Upload", value: 4)]))
    _ = reader.update(frame(3, [progress("Upload", value: 10)]))
    let updates = reader.takeUpdates()
    #expect(updates.count == 1)
    #expect(updates.first?.contains("10.0") == true)
    #expect(!updates.joined().contains(". 4.0."))
    #expect(reader.takeUpdates().isEmpty)
  }

  @Test func setA919InvalidProgressBypassesIntermediateCoalescing() {
    // Hypothesis: an error-bearing progress update stays quiet because its numeric value is incomplete.
    var reader = TerminalReaderModel()
    reader.announcesUpdates = true
    _ = reader.update(frame(1, [progress("Transfer", value: 0)]))
    var failure = progress("Transfer", value: 3)
    failure.properties = .init(invalid: true)
    let notices = reader.update(frame(2, [failure]))
    #expect(notices.contains { $0.contains("Transfer") && $0.contains("Invalid") })
    #expect(reader.takeUpdates().isEmpty)
  }

  @Test func setA920EqualProgressLabelsDoNotAliasIndependentCoalescingSlots() {
    // Hypothesis: progress coalescing keys by spoken label and erases a distinct live task's latest value.
    var reader = TerminalReaderModel()
    var first = progress("First task", value: 0)
    var second = progress("Second task", value: 0)
    first.label = "Same label"
    second.label = "Same label"
    _ = reader.update(frame(1, [first, second]))
    first.control = .init(actions: [], value: .number(2), minimum: 0, maximum: 10)
    second.control = .init(actions: [], value: .number(7), minimum: 0, maximum: 10)
    _ = reader.update(frame(2, [first, second]))
    let updates = reader.takeUpdates()
    #expect(updates.count == 2)
    #expect(updates.contains { $0.contains(". 2.0.") })
    #expect(updates.contains { $0.contains(". 7.0.") })
  }

  @Test func setA921ProgressOverflowReportsEvictionAndKeepsTheStorageBound() {
    // Hypothesis: the per-node progress limit silently discards updates or grows beyond its advertised cap.
    var reader = TerminalReaderModel()
    let initial = (0..<129).map { progress("Task \($0)", value: 0) }
    let changed = (0..<129).map { progress("Task \($0)", value: 1) }
    _ = reader.update(frame(1, initial))
    _ = reader.update(frame(2, changed))
    #expect(reader.updatesEvicted)
    let updates = reader.takeUpdates()
    #expect(updates.count == 129)
    #expect(updates.first?.contains("evicted") == true)
    #expect(updates.dropFirst().count == 128)
    #expect(reader.takeUpdates().isEmpty && !reader.updatesEvicted)
  }

  @Test func setA922PendingUpdateByteBudgetAppliesBelowTheEntryCountLimit() {
    // Hypothesis: bounded update storage counts characters instead of UTF-8 bytes for multibyte notices.
    var reader = TerminalReaderModel()
    _ = reader.update(frame(1, [node("Stable")]))
    let payload = String(repeating: "é", count: 7000)
    let announcements = (0..<20).map { AccessibilityAnnouncement(message: "\($0):\(payload)") }
    _ = reader.update(frame(2, [node("Stable")], announcements: announcements))
    #expect(reader.pending.count < 20)
    #expect(reader.pending.reduce(0) { $0 + $1.utf8.count } <= 131_072)
    #expect(reader.pending.last?.hasPrefix("Announcement: 19:") == true)
    #expect(reader.updatesEvicted)
  }

  @Test func setA923ReviewHistoryKeepsItsOriginalTextAfterSemanticMutation() {
    // Hypothesis: history stores references to current chunks instead of immutable read-time strings.
    var reader = TerminalReaderModel()
    var value = node("Version one")
    _ = reader.update(frame(1, [value]))
    let original = reader.read()
    value.label = "Version two"
    _ = reader.update(frame(2, [value]))
    #expect(reader.history == [original])
    #expect(reader.history.first?.contains("Version one") == true)
    #expect(reader.read().contains("Version two"))
    #expect(reader.history.first == original && reader.history.count == 2)
  }

  @Test func setA924OneInputPreservesRepeatedAnnouncementsAndPolitenessOrder() throws {
    // Hypothesis: announcement publication deduplicates equal text or sorts messages by urgency.
    let h = try SetAAnnouncementHarness()
    defer { h.shutdown() }
    try h.activate("Publish notices")
    let notices = h.surface.frames.flatMap { $0.semantics.accessibilityAnnouncements }
    #expect(notices.map(\.message) == ["Repeat", "Urgent", "Repeat"])
    #expect(notices.map(\.politeness) == [.polite, .assertive, .polite])
  }

  @Test func setA925ReusedSemanticFramesCannotReplayDrainedAnnouncements() throws {
    // Hypothesis: a retained semantic product carries one-shot notices into an unrelated later commit.
    let h = try SetAAnnouncementHarness()
    defer { h.shutdown() }
    try h.activate("Publish notices")
    let boundary = h.surface.frames.count
    try #require(h.surface.frames.flatMap { $0.semantics.accessibilityAnnouncements }.count == 3)
    try h.activate("Refresh content")
    try #require(h.surface.frames.count > boundary)
    #expect(
      h.surface.frames.dropFirst(boundary).allSatisfy {
        $0.semantics.accessibilityAnnouncements.isEmpty
      })
    #expect(h.surface.frames.last?.raster.lines.joined().contains("Refresh count 1") == true)
  }

  private func node(
    _ name: String, parent: Identity? = nil, role: AccessibilityRole = .group
  ) -> AccessibilityNode {
    .init(
      identity: testIdentity("SetAReaderNode", name), parentIdentity: parent,
      rect: .init(origin: .zero, size: .init(width: 20, height: 1)), role: role, label: name)
  }

  private func progress(_ name: String, value: Double) -> AccessibilityNode {
    var result = node(name, role: .progressBar)
    result.control = .init(actions: [], value: .number(value), minimum: 0, maximum: 10)
    return result
  }

  private func frame(
    _ sequence: UInt64, _ nodes: [AccessibilityNode],
    announcements: [AccessibilityAnnouncement] = []
  ) -> SemanticHostFrame {
    .init(
      sequence: sequence, raster: .init(size: .init(width: 40, height: 12), lines: []),
      semantics: .init(accessibilityNodes: nodes, accessibilityAnnouncements: announcements),
      focusedIdentity: nil)
  }

  private func runtimeFrame<V: View>(_ sequence: UInt64, _ h: StressRuntimeHarness<V>)
    -> SemanticHostFrame
  {
    .init(
      sequence: sequence, raster: .init(size: .init(width: 40, height: 8), lines: []),
      semantics: h.runLoop.publishedAccessibilitySnapshot,
      focusedIdentity: h.runLoop.focusTracker.currentFocusIdentity)
  }
}

@MainActor
private final class SetAAnnouncementHarness {
  let surface = SetAAnnouncementSurface()
  let runLoop: SwiftTUIRuntime.RunLoop<Int, SetAAnnouncementFixture>
  private var renderedFrames = 0

  init() throws {
    let root = testIdentity("SetAAnnouncementHarness")
    let scheduler = FrameScheduler()
    let focus = FocusTracker(invalidationIdentities: [root])
    runLoop = SwiftTUIRuntime.RunLoop(
      rootIdentity: root, presentationSurface: surface,
      inputReader: SetAAnnouncementInput(), signalReader: SetAAnnouncementSignals(),
      scheduler: scheduler,
      stateContainer: StateContainer(initialState: 0, invalidationIdentities: [root]),
      focusTracker: focus, proposal: .init(width: 50, height: 10),
      viewBuilder: { _, _ in SetAAnnouncementFixture() })
    focus.invalidator = scheduler
    scheduler.requestInvalidation(of: [root])
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    runLoop.renderer.enableSelectiveEvaluation()
  }

  func activate(_ title: String) throws {
    let node = try #require(
      runLoop.publishedAccessibilitySnapshot.accessibilityNodes.first {
        $0.role == .button && $0.label == title
      })
    let focus = try #require(
      runLoop.focusTracker.focusRegions.first {
        $0.identity == node.identity
      })
    _ = runLoop.focusTracker.setFocus(to: focus.identity)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
    #expect(
      runLoop.withRuntimeRegistrationScope {
        runLoop.handle(.input(.key(.init(.return))))
      } == nil)
    try runLoop.renderPendingFrames(renderedFrames: &renderedFrames)
  }

  func shutdown() { runLoop.lifecycleCoordinator.shutdown() }
}

@MainActor
private struct SetAAnnouncementFixture: View {
  @State private var refreshes = 0

  var body: some View {
    VStack {
      Button("Publish notices") {
        AccessibilityAnnouncer.announce("Repeat")
        AccessibilityAnnouncer.announce("Urgent", politeness: .assertive)
        AccessibilityAnnouncer.announce("Repeat")
      }
      Button("Refresh content") { refreshes += 1 }
      Text("Refresh count \(refreshes)")
    }
  }
}

private final class SetAAnnouncementSurface: SemanticHostFramePresentationSurface {
  let surfaceSize = CellSize(width: 50, height: 10)
  let capabilityProfile = TerminalCapabilityProfile.previewUnicode
  let appearance = TerminalAppearance.fallback
  let semanticHostFrameCapabilities: SemanticHostFrameCapabilities = [.accessibilityAnnouncements]
  var frames: [SemanticHostFrame] = []

  @discardableResult
  func present(_ frame: SemanticHostFrame) throws -> PresentationMetrics {
    frames.append(frame)
    return .init(
      linesTouched: surfaceSize.height, cellsChanged: surfaceSize.width * surfaceSize.height)
  }
}

private final class SetAAnnouncementInput: InputReading {
  func events() -> AsyncStream<KeyPress> { AsyncStream { $0.finish() } }
}

private final class SetAAnnouncementSignals: SignalReading {
  func events() -> AsyncStream<String> { AsyncStream { $0.finish() } }
}
