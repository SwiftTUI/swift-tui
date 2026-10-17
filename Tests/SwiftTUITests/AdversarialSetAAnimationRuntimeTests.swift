import Foundation
@_spi(Testing) import SwiftTUITestSupport
import Synchronization
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAAnimationRuntimeTests {
  @Test func setA526NestedNilAnimationRestoresTheNextOwnersAnimationScope() throws {
    // Hypothesis: a nested nil scope leaks disabled intent into a later independent state owner.
    let h = try harness(526) { SetAAnimationScopeFixture() }
    defer { h.shutdown() }
    let c = h.runLoop.renderer.internalAnimationController
    let clock = SetAAnimationClock(h)
    _ = try withAnimationSinks(c) { try h.clickText("Snap nested") }
    #expect(c.activeAnimationCount == 0)
    _ = try withAnimationSinks(c) { try h.clickText("Animate outer") }
    #expect(c.debugStateSnapshot().activeAnimationKeys.contains { $0.scope == .property(.offset) })
    #expect(
      !c.debugStateSnapshot().activeAnimationKeys.contains { $0.scope == .property(.opacity) })
    try clock.advance(by: .seconds(3))
    #expect(c.activeAnimationCount == 0)
  }

  @Test func setA527NilValueGateDoesNotSuppressItsAnimatedSibling() throws {
    // Hypothesis: a changed nil gate stamps disabled intent across the enclosing sibling cohort.
    let h = try harness(527) { SetANilGateFixture() }
    defer { h.shutdown() }
    let c = h.runLoop.renderer.internalAnimationController
    let clock = SetAAnimationClock(h)
    _ = try withAnimationSinks(c) { try h.clickText("Change both") }
    let scopes = Set(c.debugStateSnapshot().activeAnimationKeys.map(\.scope))
    #expect(scopes.contains(.property(.offset)))
    #expect(!scopes.contains(.property(.opacity)))
    try clock.advance(by: .seconds(3))
  }

  @Test func setA528ValueTransactionPreservesWriteMetadataWhileChangingItsCurve() throws {
    // Hypothesis: rebuilding the gated transaction drops continuity, velocity tracking, or custom values.
    let records = SetATransactionRecords()
    let h = try harness(528) { SetAMetadataGateFixture(records: records) }
    defer { h.shutdown() }
    records.clear()
    _ = try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Keyed change")
    }
    #expect(records.values.contains("source:1:1"), "Observed metadata: \(records.values)")
  }

  @Test func setA529NestedScopedTransactionsRestoreEachPlaceholderContext() throws {
    // Hypothesis: a nested scoped body's placeholder restores the wrong ancestor's custom transaction.
    let records = SetATransactionRecords()
    let h = try harness(529) { SetAScopedMetadataFixture(records: records) }
    defer { h.shutdown() }
    records.clear()
    try h.clickText("Refresh scopes")
    #expect(records.values.contains("base:outer"), "\(records.values)")
    #expect(records.values.contains("middle:middle"), "\(records.values)")
    #expect(records.values.contains("inner:inner"), "\(records.values)")
  }

  @Test func setA530EveryCompletionOnOneTransactionFiresOnce() throws {
    // Hypothesis: multiple registered closures overwrite each other in one completion batch.
    let p = SetAAnimationProbe()
    let h = try harness(530) { SetACompletionFixture(probe: p, mode: .multiple) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      #expect(p.events.isEmpty)
      try clock.advance(by: .seconds(2))
    }
    #expect(p.events == ["first", "second", "removed"], "\(p.events)")
    expectDrained(h)
  }

  @Test func setA531CompletionCanStartASecondAnimationInItsOriginalOwner() throws {
    // Hypothesis: callback dispatch loses authoring context or drains a newly registered batch as the old one ends.
    let p = SetAAnimationProbe()
    let h = try harness(531) { SetACompletionFixture(probe: p, mode: .chained) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      try clock.advance(by: .seconds(3))
    }
    #expect(p.events == ["first", "second"], "\(p.events)")
    #expect(h.frame.contains("value=16"), "\(h.frame)")
    expectDrained(h)
  }

  @Test func setA532ThrowingAfterAStateWriteKeepsItsCompletionBatch() throws {
    // Hypothesis: unwinding a throwing scope treats an already submitted state write as an empty batch.
    let p = SetAAnimationProbe()
    let h = try harness(532) { SetACompletionFixture(probe: p, mode: .throwing) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      #expect(p.events == ["caught"])
      try clock.advance(by: .seconds(2))
    }
    #expect(p.events == ["caught", "finished"], "\(p.events)")
    #expect(h.frame.contains("value=8"))
    expectDrained(h)
  }

  @Test func setA533NetZeroWritesStillRetireTheirCompletion() throws {
    // Hypothesis: writes which return to the original value leave an unclaimed batch with no active property slot.
    let p = SetAAnimationProbe()
    let h = try harness(533) { SetACompletionFixture(probe: p, mode: .netZero) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      try clock.advance(by: .seconds(2))
    }
    #expect(p.events == ["finished"], "\(p.events)")
    #expect(h.frame.contains("value=0"))
    expectDrained(h)
  }

  @Test func setA534IndependentOwnersKeepSeparateCompletionBatches() throws {
    // Hypothesis: a short animation drains another owner's longer completion batch in the same frame cohort.
    let p = SetAAnimationProbe()
    let h = try harness(534) {
      VStack {
        SetAIndependentAnimation(label: "Short", duration: .milliseconds(200), probe: p)
        SetAIndependentAnimation(label: "Long", duration: .seconds(1), probe: p)
      }
    }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Short")
      try h.clickText("Long")
      try clock.advance(by: .milliseconds(400))
      #expect(p.events == ["Short"], "\(p.events)")
      try clock.advance(by: .seconds(2))
    }
    #expect(p.events == ["Short", "Long"], "\(p.events)")
    expectDrained(h)
  }

  @Test func setA535InterruptedAnimationCompletesEachSubmittedBatchOnce() throws {
    // Hypothesis: retargeting one slot either leaks its previous batch or fires the replacement completion twice.
    let p = SetAAnimationProbe()
    let h = try harness(535) { SetACompletionFixture(probe: p, mode: .interrupted) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      try clock.advance(by: .milliseconds(100))
      try h.clickText("Reverse")
      try clock.advance(by: .seconds(3))
    }
    #expect(p.events.filter { $0 == "first" }.count == 1, "\(p.events)")
    #expect(p.events.filter { $0 == "replacement" }.count == 1, "\(p.events)")
    #expect(h.frame.contains("value=0"))
    expectDrained(h)
  }

  @Test func setA536ReentrantEmptyCompletionDoesNotLoseNestedCallback() throws {
    // Hypothesis: an empty completion registered while callbacks are being drained is discarded by ledger cleanup.
    let p = SetAAnimationProbe()
    let h = try harness(536) { SetACompletionFixture(probe: p, mode: .reentrant) }
    defer { h.shutdown() }
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(h.runLoop.renderer.internalAnimationController) {
      try h.clickText("Start")
      try clock.advance(by: .seconds(2))
    }
    #expect(p.events == ["first", "nested"], "\(p.events)")
    expectDrained(h)
  }

  @Test func setA537RemovalOverlayDoesNotRetainInteractiveSemantics() throws {
    // Hypothesis: visual exit retention leaves a removed button in the published accessibility and action tree.
    let p = SetAAnimationProbe()
    let h = try harness(537) { SetARemovalFixture(probe: p) }
    defer { h.shutdown() }
    let c = h.runLoop.renderer.internalAnimationController
    let clock = SetAAnimationClock(h)
    #expect(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Departing"
      })
    _ = try withAnimationSinks(c) { try h.clickText("Hide") }
    #expect(!c.debugStateSnapshot().removingIdentities.isEmpty)
    #expect(
      !h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.contains {
        $0.label == "Departing"
      })
    try clock.advance(by: .seconds(3))
    #expect(p.events == ["removed"])
    expectDrained(h)
  }

  @Test func setA538ReinsertionDuringExitPublishesOneFreshInteractiveOwner() throws {
    // Hypothesis: reinserting a conditional identity while its exit overlay survives duplicates or disables the new action.
    let p = SetAAnimationProbe()
    let h = try harness(538) { SetARemovalFixture(probe: p) }
    defer { h.shutdown() }
    let c = h.runLoop.renderer.internalAnimationController
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(c) {
      try h.clickText("Hide")
      #expect(!c.debugStateSnapshot().removingIdentities.isEmpty)
      try h.clickText("Show")
      try h.clickText("Departing")
      try clock.advance(by: .seconds(3))
    }
    #expect(p.events.filter { $0 == "pressed" }.count == 1, "\(p.events)")
    #expect(
      h.runLoop.publishedAccessibilitySnapshot.accessibilityNodes.filter { $0.label == "Departing" }
        .count == 1)
    #expect(c.debugStateSnapshot().removingIdentities.isEmpty)
  }

  @Test func setA539DisabledInsertionSettlesTransitionBeforeCompletion() throws {
    // Hypothesis: an explicit nil insertion still registers transition work and delays its completion.
    let p = SetAAnimationProbe()
    let h = try harness(539) { SetADisabledInsertionFixture(probe: p) }
    defer { h.shutdown() }
    let c = h.runLoop.renderer.internalAnimationController
    let clock = SetAAnimationClock(h)
    try withAnimationSinks(c) {
      try h.clickText("Insert disabled")
      #expect(
        p.events == ["finished"], "Disabled insertion should complete on its committed input frame")
      #expect(c.activeAnimationCount == 0)
      try clock.advance(by: .seconds(1))
    }
    #expect(h.frame.contains("Inserted"))
    #expect(p.events == ["finished"])
    #expect(c.activeAnimationCount == 0)
    #expect(c.debugStateSnapshot().removingIdentities.isEmpty)
    expectDrained(h)
  }

  @Test func setA540CollidingPhaseTriggerHashesStillRunDistinctCycles() async throws {
    // Hypothesis: task identity stores a trigger hash and conflates different values with the same hash.
    let p = SetAAnimationProbe()
    let calls = SetAPhaseCalls()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA540") {
      SetAPhaseFixture(probe: p, calls: calls, mode: .collision)
    }
    defer { h.shutdown() }
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { calls.values.count >= 3 && p.phases.last == 0 })
    let before = calls.values.count
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { calls.values.count >= before + 3 && p.phases.last == 0 })
    #expect(calls.values == [1, 2, 0, 1, 2, 0], "\(calls.values)")
  }

  @Test func setA541EqualAdjacentPhasesDoNotSkipAnAuthoredStep() async throws {
    // Hypothesis: equality-based phase lookup collapses duplicate adjacent indices and omits a later phase.
    let p = SetAAnimationProbe()
    let calls = SetAPhaseCalls()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA541") {
      SetAPhaseFixture(probe: p, calls: calls, mode: .duplicates)
    }
    defer { h.shutdown() }
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { calls.values.count >= 4 && p.phases.last == 0 })
    #expect(calls.values == [1, 1, 2, 0], "\(calls.values)")
  }

  @Test func setA542SinglePhaseTriggerCompletesWithoutSchedulingAnAnimation() async throws {
    // Hypothesis: a single-phase trigger enters the cycle loop and creates self-transition work indefinitely.
    let p = SetAAnimationProbe()
    let calls = SetAPhaseCalls()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA542") {
      SetAPhaseFixture(probe: p, calls: calls, mode: .single)
    }
    defer { h.shutdown() }
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { h.activeTaskCount == 0 })
    #expect(calls.values.isEmpty)
    #expect(p.phases.allSatisfy { $0 == 0 })
    #expect(h.runLoop.renderer.internalAnimationController.activeAnimationCount == 0)
  }

  @Test func setA543RemovingAnInfinitePhaseRetiresItsRegistrationAndRemountsAtRest() async throws {
    // Hypothesis: removing a phase waiting on an infinite curve retains its task registration or remounts stale phase state.
    let p = SetAAnimationProbe()
    let calls = SetAPhaseCalls()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA543") {
      SetAPhaseFixture(probe: p, calls: calls, mode: .infinite)
    }
    defer { h.shutdown() }
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { p.phases.last == 1 })
    try phaseClick("Hide phase", in: h)
    try await h.wait(until: { h.activeTaskCount == 0 })
    #expect(!h.frame.contains("phase="))
    try phaseClick("Show phase", in: h)
    #expect(h.frame.contains("phase=0"))
  }

  @Test func setA544NilPhaseCurvesStillAdvanceThroughTheEntireCycle() async throws {
    // Hypothesis: a snapped phase creates no property animation and never releases the phase driver's completion gate.
    let p = SetAAnimationProbe()
    let calls = SetAPhaseCalls()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA544") {
      SetAPhaseFixture(probe: p, calls: calls, mode: .nilCurves)
    }
    defer { h.shutdown() }
    try phaseClick("Trigger", in: h)
    try await h.wait(until: { calls.values.count >= 3 && p.phases.last == 0 })
    #expect(calls.values == [1, 2, 0])
    #expect(h.runLoop.renderer.internalAnimationController.activeAnimationCount == 0)
  }

  @Test func setA545KeyframeTriggerNeedsEqualityWithoutHashability() async throws {
    // Hypothesis: erased task-key equality accidentally requires a Hashable trigger despite the public Equatable contract.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA545") {
      SetAKeyframeFixture(probe: p)
    }
    defer { h.shutdown() }
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 10 })
    #expect(p.values.first == 0)
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 20 })
    #expect(p.values.allSatisfy { $0 >= 0 && $0 <= 20 })
  }

  @Test func setA546ZeroDurationKeyframeDriverPublishesItsEndpoint() async throws {
    // Hypothesis: the driver's zero-duration fast path exits before committing its final move to view state.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA546") { SetAZeroKeyframeFixture(probe: p) }
    defer { h.shutdown() }
    try h.clickText("Instant keyframe")
    try await h.wait(until: { p.values.last == 9 })
    #expect(h.frame.contains("instant=9"))
    #expect(!p.values.contains(4), "The same zero-time boundary should publish only its last move")
  }

  @Test func setA547InFlightKeyframesKeepTheirBuilderUntilTheNextTrigger() async throws {
    // Hypothesis: a parent body update replaces an in-flight timeline or the next trigger retains an obsolete builder.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA547") {
      SetAKeyframeFixture(probe: p, switchBuilderOnConstruction: true)
    }
    defer { h.shutdown() }
    // The first builder changes its parent binding after capturing its endpoint, before
    // the driver can take a first sample. This establishes an in-flight update without
    // requiring a wall-clock intermediate frame on a loaded runner.
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 10 })
    #expect(p.events == ["builder switched"])
    #expect(p.values.allSatisfy { $0 <= 10 }, "\(p.values)")
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 30 })
    #expect(h.frame.contains("value=30"))
  }

  @Test func setA548ShorterKeyframeTrackHoldsItsEndpointUntilTheLongestEnds() async throws {
    // Hypothesis: the runtime finishes at the first track's duration or resets a completed track while another advances.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA548") { SetAMultitrackFixture(probe: p) }
    defer { h.shutdown() }
    try h.clickText("Multitrack")
    try await h.wait(until: { p.pairs.last == SetAKeyframePair(x: 4, y: 12) })
    let afterShortEndpoint = p.pairs.drop { $0.x != 4 }
    #expect(!afterShortEndpoint.isEmpty)
    #expect(afterShortEndpoint.allSatisfy { $0.x == 4 }, "\(p.pairs)")
    #expect(p.pairs.filter { $0.y >= 4 }.allSatisfy { $0.x == 4 })
  }

  @Test func setA549RemovingARepeatingKeyframeReleasesItsTaskAndRemountsAtTheSeed() async throws {
    // Hypothesis: a removed repeating driver survives and writes its old phase into a new conditional owner.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA549") {
      SetARepeatingKeyframeFixture(probe: p)
    }
    defer { h.shutdown() }
    try await h.wait(until: { (p.values.last ?? 0) > 1 })
    try h.clickText("Hide repeat")
    try await h.wait(until: { h.activeTaskCount == 0 })
    let before = p.values.count
    try h.clickText("Show repeat")
    #expect(p.values.dropFirst(before).first == 0, "\(p.values.dropFirst(before))")
    try await h.wait(until: { p.values.count > before + 1 && (p.values.last ?? 0) > 0 })
    #expect(h.activeTaskCount == 1)
  }

  @Test func setA550ChangingInitialValueDoesNotResetARetainedKeyframeOwner() async throws {
    // Hypothesis: a parent re-evaluation re-seeds the animator's state from a changed initialValue without a new identity.
    let p = SetAAnimationProbe()
    let h = try AnimatorRuntimeHarness(rootLabel: "SetA550") {
      SetAKeyframeFixture(probe: p)
    }
    defer { h.shutdown() }
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 10 })
    let before = p.values.count
    try h.clickText("Change initial")
    #expect(p.values.last == 10)
    #expect(p.values.dropFirst(before).allSatisfy { $0 == 10 })
    try h.clickText("Trigger keyframe")
    try await h.wait(until: { p.values.last == 20 })
  }

  @discardableResult
  private func phaseClick<V: View>(_ label: String, in harness: AnimatorRuntimeHarness<V>) throws
    -> String
  {
    // Match RunLoop.run's ambient registration scope. A lifecycle task inherits
    // the task locals of the synchronous frame that starts it; the bare harness
    // otherwise drops withAnimation completion registrations from its phase driver.
    try harness.runLoop.withRuntimeRegistrationScope { try harness.clickText(label) }
  }

  private func harness<V: View>(_ id: Int, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAAnimation\(id)"), size: .init(width: 70, height: 12),
      content: content)
  }

  private func expectDrained<V: View>(_ h: StressRuntimeHarness<V>) {
    let state = h.runLoop.renderer.internalAnimationController.debugStateSnapshot()
    #expect(state.activeAnimationKeys.isEmpty)
    #expect(state.completionClosureBatchIDs.isEmpty)
    #expect(state.unclaimedCompletionBatchIDs.isEmpty)
  }
}

@MainActor
private final class SetAAnimationProbe {
  var events: [String] = []
  var phases: [Int] = []
  var values: [Double] = []
  var pairs: [SetAKeyframePair] = []
}

private final class SetATransactionRecords: Sendable {
  private let storage = Mutex<[String]>([])
  var values: [String] { storage.withLock { $0 } }
  func append(_ value: String) { storage.withLock { $0.append(value) } }
  func clear() { storage.withLock { $0.removeAll() } }
}

private final class SetAPhaseCalls: Sendable {
  private let storage = Mutex<[Int]>([])
  var values: [Int] { storage.withLock { $0 } }
  func append(_ value: Int) { storage.withLock { $0.append(value) } }
}

@MainActor
private final class SetAAnimationTime {
  var now = MonotonicInstant.now()
}

@MainActor
private final class SetAAnimationClock<V: View> {
  private let harness: StressRuntimeHarness<V>
  private let time = SetAAnimationTime()
  init(_ harness: StressRuntimeHarness<V>) {
    self.harness = harness
    // The run loop retains only the time box, not this clock and its harness.
    harness.runLoop.frameClock = { [time] in time.now }
  }
  func advance(by duration: Duration) throws {
    let target = time.now.advanced(by: duration)
    var turns = 0
    while turns < 2_000 {
      guard let wake = harness.runLoop.scheduler.nextWakeInstant(after: time.now), wake <= target
      else {
        break
      }
      time.now = wake
      _ = try harness.render()
      turns += 1
    }
    #expect(turns < 2_000, "Animation fixture did not drain its scheduled turns")
    time.now = target
  }
}

@MainActor
private struct SetAAnimationScopeFixture: View {
  @State private var offset = 0
  var body: some View {
    VStack {
      Button("Animate outer") { withAnimation(.linear(duration: .seconds(1))) { offset = 8 } }
      Text("animated").offset(x: offset, y: 0)
      SetANestedNilOwner()
    }
  }
}

@MainActor
private struct SetANestedNilOwner: View {
  @State private var faded = false
  var body: some View {
    VStack {
      Button("Snap nested") {
        withAnimation(.linear(duration: .seconds(1))) {
          withAnimation(nil) { faded = true }
        }
      }
      Text("snap").opacity(faded ? 0.3 : 1)
    }
  }
}

@MainActor
private struct SetANilGateFixture: View {
  @State private var changed = false
  var body: some View {
    VStack {
      Button("Change both") { withAnimation(.linear(duration: .seconds(1))) { changed.toggle() } }
      Text("snap").opacity(changed ? 0.2 : 1).animation(nil, value: changed)
      Text("move").offset(x: changed ? 8 : 0, y: 0)
    }
  }
}

private enum SetAAnimationSourceKey: TransactionKey { static let defaultValue = "default" }

@MainActor
private struct SetAMetadataGateFixture: View {
  let records: SetATransactionRecords
  @State private var gate = 0
  var body: some View {
    VStack {
      Button("Keyed change") {
        var transaction = Transaction(animation: .linear(duration: .seconds(1)))
        transaction.isContinuous = true
        transaction.tracksVelocity = true
        transaction[SetAAnimationSourceKey.self] = "source"
        withTransaction(transaction) { gate += 1 }
      }
      Text("metadata \(gate)").offset(x: gate, y: 0)
        .transaction { transaction in
          records.append(
            "\(transaction[SetAAnimationSourceKey.self]):\(transaction.isContinuous ? 1 : 0):\(transaction.tracksVelocity ? 1 : 0)"
          )
        }
        .transaction(value: gate) { $0.animation = .easeOut(duration: .seconds(1)) }
    }
  }
}

@MainActor
private struct SetAScopedMetadataFixture: View {
  let records: SetATransactionRecords
  @State private var revision = 0
  var body: some View {
    VStack {
      Button("Refresh scopes") { revision += 1 }
      Text("base \(revision)")
        .transaction { records.append("base:\($0[SetAAnimationSourceKey.self])") }
        .transaction({ $0[SetAAnimationSourceKey.self] = "middle" }) { base in
          VStack {
            base
            Text("middle \(revision)")
              .transaction { records.append("middle:\($0[SetAAnimationSourceKey.self])") }
          }
          .transaction({ $0[SetAAnimationSourceKey.self] = "inner" }) { middle in
            VStack {
              middle
              Text("inner \(revision)")
                .transaction { records.append("inner:\($0[SetAAnimationSourceKey.self])") }
            }
          }
        }
        .transaction { $0[SetAAnimationSourceKey.self] = "outer" }
    }
  }
}

private enum SetACompletionMode {
  case multiple, chained, throwing, netZero, interrupted, reentrant
}
private enum SetAAnimationFailure: Error { case expected }

@MainActor
private struct SetACompletionFixture: View {
  let probe: SetAAnimationProbe
  let mode: SetACompletionMode
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Start") { start() }
      Button("Reverse") {
        withAnimation(.linear(duration: .milliseconds(300))) {
          value = 0
        } completion: {
          probe.events.append("replacement")
        }
      }
      Text("marker").offset(x: value, y: 0)
      Text("value=\(value)")
    }
  }
  private func start() {
    let curve = Animation.linear(duration: .milliseconds(400))
    switch mode {
    case .multiple:
      var transaction = Transaction(animation: curve)
      transaction.addAnimationCompletion { probe.events.append("first") }
      transaction.addAnimationCompletion { probe.events.append("second") }
      transaction.addAnimationCompletion(criteria: .removed) { probe.events.append("removed") }
      withTransaction(transaction) { value = 8 }
    case .chained:
      withAnimation(curve) {
        value = 8
      } completion: {
        probe.events.append("first")
        withAnimation(curve) {
          value = 16
        } completion: {
          probe.events.append("second")
        }
      }
    case .throwing:
      do {
        try withAnimation(curve) {
          value = 8
          throw SetAAnimationFailure.expected
        } completion: {
          probe.events.append("finished")
        }
      } catch { probe.events.append("caught") }
    case .netZero:
      withAnimation(curve) {
        value = 8
        value = 0
      } completion: {
        probe.events.append("finished")
      }
    case .interrupted:
      withAnimation(curve) {
        value = 8
      } completion: {
        probe.events.append("first")
      }
    case .reentrant:
      withAnimation(curve) {
        value = 8
      } completion: {
        probe.events.append("first")
        withAnimation(nil) {
        } completion: {
          probe.events.append("nested")
        }
      }
    }
  }
}

@MainActor
private struct SetAIndependentAnimation: View {
  let label: String
  let duration: Duration
  let probe: SetAAnimationProbe
  @State private var shifted = false
  var body: some View {
    VStack {
      Button(label) {
        withAnimation(.linear(duration: duration)) {
          shifted = true
        } completion: {
          probe.events.append(label)
        }
      }
      Text("\(label) marker").offset(x: shifted ? 8 : 0, y: 0)
    }
  }
}

@MainActor
private struct SetARemovalFixture: View {
  let probe: SetAAnimationProbe
  @State private var shown = true
  var body: some View {
    VStack(alignment: .leading) {
      Button("Hide") {
        withAnimation(.linear(duration: .seconds(1)), completionCriteria: .removed) {
          shown = false
        } completion: {
          probe.events.append("removed")
        }
      }
      Button("Show") { withAnimation(nil) { shown = true } }
      if shown { Button("Departing") { probe.events.append("pressed") }.transition(.opacity) }
    }
  }
}

@MainActor
private struct SetADisabledInsertionFixture: View {
  let probe: SetAAnimationProbe
  @State private var shown = false
  var body: some View {
    VStack {
      Button("Insert disabled") {
        withAnimation(nil, completionCriteria: .removed) {
          shown = true
        } completion: {
          probe.events.append("finished")
        }
      }
      if shown { Text("Inserted").transition(.move(edge: .leading).combined(with: .opacity)) }
    }
  }
}

private struct SetACollidingPhaseTrigger: Hashable, Sendable {
  var value: Int
  func hash(into hasher: inout Hasher) { hasher.combine(0) }
}
private enum SetAPhaseMode: Sendable { case collision, duplicates, single, infinite, nilCurves }

@MainActor
private struct SetAPhaseFixture: View {
  let probe: SetAAnimationProbe
  let calls: SetAPhaseCalls
  let mode: SetAPhaseMode
  @State private var trigger = 0
  @State private var shown = true
  private var phases: [Int] {
    switch mode {
    case .single: [0]
    case .duplicates: [0, 1, 1, 2]
    default: [0, 1, 2]
    }
  }
  var body: some View {
    let mode = self.mode
    let calls = self.calls
    return VStack {
      Button("Trigger") { trigger += 1 }
      Button(shown ? "Hide phase" : "Show phase") { shown.toggle() }
      if shown {
        PhaseAnimator(phases, trigger: SetACollidingPhaseTrigger(value: trigger)) { phase in
          let _ = probe.phases.append(phase)
          Text("phase=\(phase)").offset(x: phase * 4, y: 0)
        } animation: { phase in
          calls.append(phase)
          switch mode {
          case .nilCurves: return nil
          case .infinite: return .linear(duration: .seconds(1)).repeatForever(autoreverses: false)
          default: return .linear(duration: .milliseconds(60))
          }
        }
      }
    }
  }
}

private struct SetAEquatableKeyframeTrigger: Equatable { var values: [Int] }

@MainActor
private struct SetAKeyframeFixture: View {
  let probe: SetAAnimationProbe
  var switchBuilderOnConstruction = false
  @State private var trigger = 0
  @State private var changedBuilder = false
  @State private var changedInitial = false
  var body: some View {
    let increment = changedBuilder ? 20.0 : 10.0
    let builderBinding = $changedBuilder
    return VStack {
      Button("Trigger keyframe") { trigger += 1 }
      Button("Change builder") { changedBuilder.toggle() }
      Button("Change initial") { changedInitial.toggle() }
      KeyframeAnimator(
        initialValue: changedInitial ? 100.0 : 0.0,
        trigger: SetAEquatableKeyframeTrigger(values: [trigger])
      ) { value in
        let _ = probe.values.append(value)
        Text("value=\(Int(value))")
      } keyframes: { start in
        let _ = switchBuilderIfRequested(builderBinding)
        LinearKeyframe(start + increment, duration: .milliseconds(350))
      }
    }
  }

  private func switchBuilderIfRequested(_ binding: Binding<Bool>) {
    guard switchBuilderOnConstruction, !binding.wrappedValue else { return }
    binding.wrappedValue = true
    probe.events.append("builder switched")
  }
}

@MainActor
private struct SetAZeroKeyframeFixture: View {
  let probe: SetAAnimationProbe
  @State private var trigger = 0
  var body: some View {
    VStack {
      Button("Instant keyframe") { trigger += 1 }
      KeyframeAnimator(initialValue: 0.0, trigger: trigger) { value in
        let _ = probe.values.append(value)
        Text("instant=\(Int(value))")
      } keyframes: { _ in
        MoveKeyframe(4)
        MoveKeyframe(9)
      }
    }
  }
}

private struct SetAKeyframePair: Equatable, Sendable {
  var x = 0.0
  var y = 0.0
}

@MainActor
private struct SetAMultitrackFixture: View {
  let probe: SetAAnimationProbe
  @State private var trigger = 0
  var body: some View {
    VStack {
      Button("Multitrack") { trigger += 1 }
      KeyframeAnimator(initialValue: SetAKeyframePair(), trigger: trigger) { value in
        let _ = probe.pairs.append(value)
        Text("pair=\(Int(value.x)),\(Int(value.y))")
      } keyframes: { _ in
        KeyframeTrack(\.x) { LinearKeyframe(4, duration: .milliseconds(150)) }
        KeyframeTrack(\.y) { LinearKeyframe(12, duration: .milliseconds(600)) }
      }
    }
  }
}

@MainActor
private struct SetARepeatingKeyframeFixture: View {
  let probe: SetAAnimationProbe
  @State private var shown = true
  var body: some View {
    VStack {
      Button(shown ? "Hide repeat" : "Show repeat") { shown.toggle() }
      if shown {
        KeyframeAnimator(initialValue: 0.0, repeating: true) { value in
          let _ = probe.values.append(value)
          Text("repeat=\(Int(value))")
        } keyframes: { _ in
          LinearKeyframe(8, duration: .milliseconds(600))
        }
      }
    }
  }
}
