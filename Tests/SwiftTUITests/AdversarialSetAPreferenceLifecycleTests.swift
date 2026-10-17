import Observation
@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAPreferenceLifecycleTests {
  @Test func setA301RemovingLastWriterPublishesTheDefaultValue() throws {
    // Hypothesis: a retained ancestor keeps its last non-default fold when its final writer leaves.
    let log = SetAPreferenceLog()
    let h = try make("301") { SetALastPreferenceWriter(log: log) }
    defer { h.shutdown() }
    try #require(log.values == [["present"]])
    try h.clickText("Remove writer")
    #expect(log.values == [["present"], []], "\(log.values)")
    try h.clickText("Remove writer")
    #expect(log.values == [["present"], [], ["present"]], "\(log.values)")
  }

  @Test func setA302ReducerCanDeclineLaterSiblingContributions() {
    // Hypothesis: generic preference merging overwrites a reducer that deliberately skips nextValue.
    let node = Resolver().resolve(
      VStack {
        Text("empty").preference(key: SetAFirstPreferenceKey.self, value: "")
        Text("first").preference(key: SetAFirstPreferenceKey.self, value: "first")
        Text("second").preference(key: SetAFirstPreferenceKey.self, value: "second")
      }, in: .init(identity: testIdentity("SetA302")))
    #expect(node.preferenceValues[SetAFirstPreferenceKey.self] == "first")
  }

  @Test func setA303NestedObserversKeepTheirSubtreeBoundaries() throws {
    // Hypothesis: same-key observation registration reads an ancestor's aggregate for an inner owner.
    let log = SetAPreferenceLog()
    let h = try make("303") { SetANestedPreferenceObservers(log: log) }
    defer { h.shutdown() }
    try #require(log.events.contains("inner:left0"))
    try #require(log.events.contains("outer:left0,right"))
    log.events.removeAll()
    try h.clickText("Change left")
    #expect(log.events.sorted() == ["inner:left1", "outer:left1,right"])
  }

  @Test func setA304PreferenceCallbackStateWriteSettlesWithoutRepeatedDelivery() throws {
    // Hypothesis: post-commit preference callbacks lose their state invalidation or repeat on its frame.
    let log = SetAPreferenceLog()
    let h = try make("304") { SetAPreferenceFeedback(log: log) }
    defer { h.shutdown() }
    try #require(h.frame.contains("mirror=seed0"), "\(h.frame)")
    try #require(log.values == [["seed0"]])
    try h.clickText("Advance feedback")
    #expect(h.frame.contains("mirror=seed1"), "\(h.frame)")
    #expect(log.values == [["seed0"], ["seed1"]], "\(log.values)")
    try h.render()
    #expect(log.values.count == 2)
  }

  @Test func setA305UnchangedPreferenceRefreshesCallbackWithoutNotifying() throws {
    // Hypothesis: equality suppression preserves an obsolete action closure along with the baseline.
    let log = SetAPreferenceLog()
    let h = try make("305") { SetAPreferenceCallbackRefresh(log: log) }
    defer { h.shutdown() }
    try #require(log.events == ["old:value0"])
    log.events.removeAll()
    try h.clickText("Replace callback")
    #expect(log.events.isEmpty)
    try h.clickText("Advance value")
    #expect(log.events == ["new:value1"], "\(log.events)")
  }

  @Test func setA306PreferenceOverlayDoesNotConsumeItsOwnOutput() throws {
    // Hypothesis: late reconciliation feeds the overlay's emitted preference back into its own input.
    let log = SetAPreferenceLog()
    let h = try make("306") { SetASelfEmittingPreferenceOverlay(log: log) }
    defer { h.shutdown() }
    try #require(h.frame.contains("overlay-input=base0"))
    try h.clickText("Advance overlay")
    #expect(h.frame.contains("overlay-input=base1"), "\(h.frame)")
    #expect(log.values.last == ["base1", "overlay"], "\(log.values)")
    #expect(!h.frame.contains("base1,overlay"))
  }

  @Test func setA307BackgroundPreferencePrecedesItsTransformedBaseInParentReduction() {
    // Hypothesis: decoration primary-child indexing reverses noncommutative background reduction.
    let node = Resolver().resolve(
      Text("base")
        .preference(key: SetAStringPreferenceKey.self, value: ["base"])
        .transformPreference(SetAStringPreferenceKey.self) { $0.append("transformed") }
        .backgroundPreferenceValue(SetAStringPreferenceKey.self) { input in
          Text(input.joined(separator: ","))
            .preference(key: SetAStringPreferenceKey.self, value: ["background"])
        }
        .preference(key: SetAStringPreferenceKey.self, value: ["outer"]),
      in: .init(identity: testIdentity("SetA307")))
    #expect(
      node.preferenceValues[SetAStringPreferenceKey.self]
        == ["background", "base", "transformed", "outer"])
  }

  @Test func setA308ClearingPreferenceAboveObserverDoesNotEraseItsLocalValue() throws {
    // Hypothesis: an in-place transform mutates storage shared with the inner observer's snapshot.
    let log = SetAPreferenceLog()
    let h = try make("308") { SetAMaskedPreference(log: log) }
    defer { h.shutdown() }
    try #require(log.events == ["inner:raw0"])
    try h.clickText("Advance masked")
    #expect(log.events == ["inner:raw0", "inner:raw1"], "\(log.events)")
    #expect(log.values.isEmpty, "Outer default must remain silent: \(log.values)")
  }

  @Test func setA309PreferenceReductionFollowsCurrentKeyedWriterOrder() throws {
    // Hypothesis: retained ForEach child outputs are folded in allocation order after reordering.
    let log = SetAPreferenceLog()
    let h = try make("309") { SetAOrderedPreferenceWriters(log: log) }
    defer { h.shutdown() }
    try #require(log.values.last == ["A", "B", "C"])
    try h.clickText("Rotate writers")
    #expect(log.values.last == ["B", "C", "A"], "\(log.values)")
    try h.clickText("Rotate writers")
    #expect(log.values.last == ["C", "A", "B"], "\(log.values)")
  }

  @Test func setA310RemovedPreferenceObserverCannotReceiveChangedSiblingValue() throws {
    // Hypothesis: committed observer carry-forward dispatches a removed callback after tree teardown.
    let log = SetAPreferenceLog()
    let h = try make("310") { SetARetiringPreferenceObserver(log: log) }
    defer { h.shutdown() }
    try #require(log.values == [["value0"]])
    try #require(h.preferenceObservationRegistrationCount == 1)
    log.values.removeAll()
    try h.clickText("Retire observer")
    #expect(log.values.isEmpty, "\(log.values)")
    #expect(h.preferenceObservationRegistrationCount == 0)
    try h.clickText("Advance retired")
    #expect(log.values.isEmpty)
  }

  @Test func setA311StableBoundsAnchorResolvesNewSizeAfterLayoutMutation() throws {
    // Hypothesis: an unchanged opaque anchor token retains the old placed size after a state resize.
    let log = SetAPreferenceLog()
    let h = try make("311") { SetAResizingAnchor(log: log) }
    defer { h.shutdown() }
    try #require(log.rects["bounds"]?.size == .init(width: 8, height: 2))
    try h.clickText("Resize anchor")
    #expect(log.rects["bounds"]?.size == .init(width: 17, height: 4), "\(log.rects)")
  }

  @Test func setA312AnchorInsideOffsetTracksTranslatedSource() throws {
    // Hypothesis: anchor lookup uses the unmoved offset wrapper's frame instead of its captured child.
    let log = SetAPreferenceLog()
    let h = try make("312") { SetAOffsetAnchor(log: log) }
    defer { h.shutdown() }
    try #require(log.rects["bounds"]?.origin == .init(x: 2, y: 1), "\(log.rects)")
    try h.clickText("Move anchor")
    #expect(log.rects["bounds"]?.origin == .init(x: 7, y: 3), "\(log.rects)")
  }

  @Test func setA313TransformAnchorCapturesItsOwnWrapperBounds() throws {
    // Hypothesis: transformAnchorPreference reuses the descendant anchor rather than its own frame.
    let log = SetAPreferenceLog()
    let h = try make("313") {
      Text("inner")
        .frame(width: 5, height: 1)
        .anchorPreference(key: SetABoundsListPreferenceKey.self, value: .bounds) { [$0] }
        .frame(width: 20, height: 4, alignment: .topLeading)
        .transformAnchorPreference(SetABoundsListPreferenceKey.self, value: .bounds) {
          $0.append($1)
        }
        .overlayPreferenceValue(SetABoundsListPreferenceKey.self) { anchors in
          GeometryReader { proxy in
            captureRects(anchors, proxy: proxy, log: log)
          }
        }
    }
    defer { h.shutdown() }
    #expect(log.rects["0"]?.size == .init(width: 5, height: 1), "\(log.rects)")
    #expect(log.rects["1"]?.size == .init(width: 20, height: 4), "\(log.rects)")
  }

  @Test func setA314PointAnchorSourceChangesWithoutChangingSourceIdentity() throws {
    // Hypothesis: anchor equality or retained geometry drops a changed point kind on the same node.
    let log = SetAPreferenceLog()
    let h = try make("314") { SetASwitchingPointAnchor(log: log) }
    defer { h.shutdown() }
    try #require(log.points.last == .zero, "\(log.points)")
    try h.clickText("Switch corner")
    #expect(log.points.last == .init(x: 12, y: 4), "\(log.points)")
  }

  @Test func setA315AnchorResolutionSubtractsTheReadingGeometryOrigin() throws {
    // Hypothesis: cross-sibling anchor conversion returns global geometry instead of reader-local space.
    let log = SetAPreferenceLog()
    let h = try make("315") {
      HStack(alignment: .top, spacing: 0) {
        Text("prefix").frame(width: 7, height: 1)
        Text("source")
          .frame(width: 8, height: 2)
          .anchorPreference(key: SetABoundsPreferenceKey.self, value: .bounds) { $0 }
      }
      .frame(width: 30, height: 4, alignment: .topLeading)
      .overlayPreferenceValue(SetABoundsPreferenceKey.self, alignment: .topLeading) { anchor in
        HStack(spacing: 0) {
          Text("").frame(width: 3, height: 1)
          GeometryReader { proxy in captureRect(anchor, proxy: proxy, log: log) }
            .frame(width: 27, height: 4)
        }
      }
    }
    defer { h.shutdown() }
    #expect(log.rects["bounds"]?.origin == .init(x: 4, y: 0), "\(log.rects)")
    #expect(log.rects["bounds"]?.size == .init(width: 8, height: 2))
  }

  @Test func setA316PreferenceDerivedTaskIsCancelledWhenItsContributionDisappears() async throws {
    // Hypothesis: late-generated decoration tasks escape teardown when their preference source empties.
    let log = SetAPreferenceLog()
    let h = try make("316") { SetAPreferenceTaskOwner(log: log) }
    try await withTaskCleanup(log: log, shutdown: h.shutdown) {
      await log.changed.wait(until: { log.events.contains("started") })
      try Task.checkCancellation()
      try #require(h.activeTaskCount == 1)
      try h.clickText("Hide task source")
      await log.changed.wait(until: { log.events.contains("cancelled") })
      try Task.checkCancellation()
      #expect(h.activeTaskCount == 0)
      #expect(h.activeTaskDescriptorCount == 0)
      #expect(log.events == ["started", "cancelled"], "\(log.events)")
    }
  }

  @Test func setA317DisappearUsesTheLastCommittedCallbackCapture() throws {
    // Hypothesis: teardown dispatch consults the initial handler closure after visible payload updates.
    let log = SetAPreferenceLog()
    let h = try make("317") { SetAFreshDisappear(log: log) }
    defer { h.shutdown() }
    try h.clickText("Refresh departing")
    try #require(h.frame.contains("departing=1"))
    try h.clickText("Remove departing")
    #expect(log.events == ["departed:1"], "\(log.events)")
  }

  @Test func setA318OnChangeCoalescesWritesWithinOneInputAction() throws {
    // Hypothesis: change baselines advance per assignment instead of comparing committed frames.
    let log = SetAPreferenceLog()
    let h = try make("318") { SetACoalescedChange(log: log) }
    defer { h.shutdown() }
    try #require(log.events.isEmpty)
    try h.clickText("Write twice")
    #expect(log.events == ["0->2"], "\(log.events)")
    try h.clickText("Write twice")
    #expect(log.events == ["0->2", "2->4"], "\(log.events)")
  }

  @Test func setA319ReinstalledNoninitialObserverPrimesAtTheCurrentValue() throws {
    // Hypothesis: a removed onChange baseline leaks into a new lifetime and emits a hidden transition.
    let log = SetAPreferenceLog()
    let h = try make("319") { SetARemountedChange(log: log) }
    defer { h.shutdown() }
    try h.clickText("Toggle change observer")
    try h.clickText("Advance change value")
    try h.clickText("Toggle change observer")
    #expect(log.events.isEmpty, "\(log.events)")
    try h.clickText("Advance change value")
    #expect(log.events == ["1->2"], "\(log.events)")
  }

  @Test func setA320AppearTriggeredSiblingInsertionDoesNotReplayParentAppearance() throws {
    // Hypothesis: an appearance callback's next frame replays the already committed parent's event.
    let log = SetAPreferenceLog()
    let h = try make("320") { SetAAppearInsertion(log: log) }
    defer { h.shutdown() }
    #expect(h.frame.contains("inserted child"), "\(h.frame)")
    #expect(log.events.filter { $0 == "parent" }.count == 1, "\(log.events)")
    #expect(log.events.filter { $0 == "child" }.count == 1, "\(log.events)")
    try h.clickText("Unrelated appearance input")
    #expect(log.events.count == 2, "\(log.events)")
  }

  @Test func setA321ObservableReadInsidePreferenceTransformInvalidatesItsConsumer() throws {
    // Hypothesis: deferred transformPreference reads escape Observation tracking and never invalidate.
    let model = SetAPreferenceObservable()
    let log = SetAPreferenceLog()
    let h = try make("321") { SetAObservedPreferenceTransform(model: model, log: log) }
    defer { h.shutdown() }
    try #require(log.values.last == ["base", "observed0"])
    model.value = 7
    try #require(model.value == 7)
    try h.render()
    withKnownIssue("STUI-978: Observable preference transforms do not register reactive reads") {
      #expect(
        log.values.last == ["base", "observed7"],
        "After an observed write, model=\(model.value), delivered preferences=\(log.values)")
    }

    // A subsequent independent root render must read the current model. This checks the
    // transform's value semantics after preserving the missing-notification assertion above.
    try h.renderAfterExternalMutation()
    #expect(log.values == [["base", "observed0"], ["base", "observed7"]], "\(log.values)")
  }

  @Test func setA322ObservableReadInsidePreferenceOverlayRearmsAfterEachMutation() throws {
    // Hypothesis: preference-derived content tracks only its first deferred observable read.
    let model = SetAPreferenceObservable()
    let h = try make("322") { SetAObservedPreferenceOverlay(model: model) }
    defer { h.shutdown() }
    try #require(h.frame.contains("observed-overlay=0"))
    for value in [3, 8] {
      model.value = value
      try h.render()
      #expect(h.frame.contains("observed-overlay=\(value)"), "\(h.frame)")
    }
  }

  @Test func setA323TypeKeyedEnvironmentModelMutationsReachAReusedReader() throws {
    // Hypothesis: instance-equal environment snapshots suppress property-level observable invalidation.
    let model = SetAPreferenceObservable()
    let h = try make("323") {
      SetAEnvironmentModelReader().environment(model)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("model=0"))
    model.value = 12
    try h.render()
    #expect(h.frame.contains("model=12"), "\(h.frame)")
  }

  @Test func setA324TypeKeyedModelsRemainDistinctWhenOnlyOneInstanceIsReplaced() throws {
    // Hypothesis: the transformEnvironment(\.self) bridge aliases independent object-type slots.
    let first = SetAPreferenceObservable()
    let replacement = SetAPreferenceObservable()
    replacement.value = 40
    let other = SetAOtherPreferenceObservable()
    let h = try make("324") {
      SetATwoEnvironmentModels(first: first, replacement: replacement, other: other)
    }
    defer { h.shutdown() }
    try #require(h.frame.contains("objects=0/9"))
    try h.clickText("Replace first model")
    #expect(h.frame.contains("objects=40/9"), "\(h.frame)")
    other.value = 13
    try h.render()
    #expect(h.frame.contains("objects=40/13"), "\(h.frame)")
    first.value = 99
    try h.render()
    #expect(h.frame.contains("objects=40/13"), "\(h.frame)")
  }

  @Test func setA325CompletedTaskPublishesStateWithoutAnInputBackstop() async throws {
    // Hypothesis: a task that returns immediately drops its owner invalidation during descriptor cleanup.
    let log = SetAPreferenceLog()
    let h = try make("325") { SetACompletingTask(log: log) }
    try await withTaskCleanup(log: log, shutdown: h.shutdown) {
      await log.changed.wait(until: { log.events.contains("completed") })
      try Task.checkCancellation()
      try h.render()
      #expect(h.frame.contains("completed-value=17"), "\(h.frame)")
      try h.clickText("Unrelated task input")
      #expect(log.events == ["completed"], "\(log.events)")
    }
  }

  private func withTaskCleanup(
    log: SetAPreferenceLog, shutdown: @MainActor () -> Void,
    operation: @MainActor () async throws -> Void
  ) async throws {
    do {
      try await operation()
    } catch {
      shutdown()
      log.releaseForCleanup()
      await log.joinTaskBodies()
      throw error
    }
    shutdown()
    log.releaseForCleanup()
    await log.joinTaskBodies()
  }

  private func make<V: View>(_ id: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetAPreferenceLifecycle", id),
      size: .init(width: 80, height: 20), content: content)
  }
}

@MainActor
private final class SetAPreferenceLog {
  let changed = MainActorConditionSignal()
  let cleanupRelease = AsyncEvent()
  private(set) var runningBodies = 0
  var events: [String] = [] { didSet { changed.notify() } }
  func releaseForCleanup() { cleanupRelease.fire() }
  func taskStarted() { runningBodies += 1 }
  func taskFinished() {
    runningBodies -= 1
    changed.notify()
  }
  func joinTaskBodies() async {
    await Task { @MainActor in
      await self.changed.wait(until: { self.runningBodies == 0 })
    }.value
  }
  var values: [[String]] = []
  var rects: [String: Rect] = [:]
  var points: [Point] = []
}

private enum SetAStringPreferenceKey: PreferenceKey {
  static let defaultValue: [String] = []
  static func reduce(value: inout [String], nextValue: () -> [String]) {
    value.append(contentsOf: nextValue())
  }
}

private enum SetAFirstPreferenceKey: PreferenceKey {
  static let defaultValue = ""
  static func reduce(value: inout String, nextValue: () -> String) {
    if value.isEmpty { value = nextValue() }
  }
}

private enum SetABoundsPreferenceKey: PreferenceKey {
  static let defaultValue: Anchor<Rect>? = nil
  static func reduce(value: inout Anchor<Rect>?, nextValue: () -> Anchor<Rect>?) {
    value = nextValue() ?? value
  }
}

private enum SetABoundsListPreferenceKey: PreferenceKey {
  static let defaultValue: [Anchor<Rect>] = []
  static func reduce(value: inout [Anchor<Rect>], nextValue: () -> [Anchor<Rect>]) {
    value.append(contentsOf: nextValue())
  }
}

private enum SetAPointPreferenceKey: PreferenceKey {
  static let defaultValue: Anchor<Point>? = nil
  static func reduce(value: inout Anchor<Point>?, nextValue: () -> Anchor<Point>?) {
    value = nextValue() ?? value
  }
}

@MainActor
private func captureRect(_ anchor: Anchor<Rect>?, proxy: GeometryProxy, log: SetAPreferenceLog)
  -> some View
{
  log.rects["bounds"] = anchor.map { proxy[$0] }
  return Text("")
}

@MainActor
private func captureRects(_ anchors: [Anchor<Rect>], proxy: GeometryProxy, log: SetAPreferenceLog)
  -> some View
{
  log.rects = Dictionary(
    uniqueKeysWithValues: anchors.enumerated().map { entry in
      (String(entry.offset), proxy[entry.element])
    })
  return Text("")
}

@MainActor
private func capturePoint(_ anchor: Anchor<Point>?, proxy: GeometryProxy, log: SetAPreferenceLog)
  -> some View
{
  if let anchor { log.points.append(proxy[anchor]) }
  return Text("")
}

@MainActor
private struct SetALastPreferenceWriter: View {
  let log: SetAPreferenceLog
  @State private var present = true
  var body: some View {
    VStack(alignment: .leading) {
      Button("Remove writer") { present.toggle() }
      if present {
        Text("writer").preference(key: SetAStringPreferenceKey.self, value: ["present"])
      }
    }
    .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
  }
}

@MainActor
private struct SetANestedPreferenceObservers: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Change left") { value += 1 }
      Text("left")
        .preference(key: SetAStringPreferenceKey.self, value: ["left\(value)"])
        .onPreferenceChange(SetAStringPreferenceKey.self) {
          log.events.append("inner:" + $0.joined(separator: ","))
        }
      Text("right").preference(key: SetAStringPreferenceKey.self, value: ["right"])
    }
    .onPreferenceChange(SetAStringPreferenceKey.self) {
      log.events.append("outer:" + $0.joined(separator: ","))
    }
  }
}

@MainActor
private struct SetAPreferenceFeedback: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  @State private var mirror = "unreported"
  var body: some View {
    VStack(alignment: .leading) {
      Button("Advance feedback") { value += 1 }
      Text("mirror=\(mirror)")
      Text("source")
        .preference(key: SetAStringPreferenceKey.self, value: ["seed\(value)"])
        .onPreferenceChange(SetAStringPreferenceKey.self) {
          log.values.append($0)
          mirror = $0.joined(separator: ",")
        }
    }
  }
}

@MainActor
private struct SetAPreferenceCallbackRefresh: View {
  let log: SetAPreferenceLog
  @State private var version = "old"
  @State private var value = 0
  var body: some View {
    let captured = version
    return VStack(alignment: .leading) {
      Button("Replace callback") { version = "new" }
      Button("Advance value") { value += 1 }
      Text("source")
        .preference(key: SetAStringPreferenceKey.self, value: ["value\(value)"])
        .onPreferenceChange(SetAStringPreferenceKey.self) {
          log.events.append(captured + ":" + $0.joined(separator: ","))
        }
    }
  }
}

@MainActor
private struct SetASelfEmittingPreferenceOverlay: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Advance overlay") { value += 1 }
      Text("base source")
        .frame(width: 60, height: 3, alignment: .topLeading)
        .preference(key: SetAStringPreferenceKey.self, value: ["base\(value)"])
        .overlayPreferenceValue(SetAStringPreferenceKey.self, alignment: .bottomLeading) { input in
          Text("overlay-input=" + input.joined(separator: ","))
            .preference(key: SetAStringPreferenceKey.self, value: ["overlay"])
        }
        .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
    }
  }
}

@MainActor
private struct SetAMaskedPreference: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Advance masked") { value += 1 }
      Text("source")
        .preference(key: SetAStringPreferenceKey.self, value: ["raw\(value)"])
        .onPreferenceChange(SetAStringPreferenceKey.self) {
          log.events.append("inner:" + $0.joined(separator: ","))
        }
        .transformPreference(SetAStringPreferenceKey.self) { $0.removeAll() }
    }
    .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
  }
}

@MainActor
private struct SetAOrderedPreferenceWriters: View {
  let log: SetAPreferenceLog
  @State private var order = ["A", "B", "C"]
  var body: some View {
    VStack(alignment: .leading) {
      Button("Rotate writers") { order.append(order.removeFirst()) }
      ForEach(order, id: \.self) { name in
        Text(name).preference(key: SetAStringPreferenceKey.self, value: [name])
      }
    }
    .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
  }
}

@MainActor
private struct SetARetiringPreferenceObserver: View {
  let log: SetAPreferenceLog
  @State private var observing = true
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Retire observer") {
        observing = false
        value += 1
      }
      Button("Advance retired") { value += 1 }
      if observing {
        Text("observed")
          .preference(key: SetAStringPreferenceKey.self, value: ["value\(value)"])
          .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
      } else {
        Text("unobserved").preference(key: SetAStringPreferenceKey.self, value: ["value\(value)"])
      }
    }
  }
}

@MainActor
private struct SetAResizingAnchor: View {
  let log: SetAPreferenceLog
  @State private var expanded = false
  var body: some View {
    VStack(alignment: .leading) {
      Button("Resize anchor") { expanded.toggle() }
      Text("source")
        .frame(width: expanded ? 17 : 8, height: expanded ? 4 : 2, alignment: .topLeading)
        .anchorPreference(key: SetABoundsPreferenceKey.self, value: .bounds) { $0 }
        .overlayPreferenceValue(SetABoundsPreferenceKey.self, alignment: .topLeading) { anchor in
          GeometryReader { proxy in captureRect(anchor, proxy: proxy, log: log) }
        }
    }
  }
}

@MainActor
private struct SetAOffsetAnchor: View {
  let log: SetAPreferenceLog
  @State private var moved = false
  var body: some View {
    VStack(alignment: .leading) {
      Button("Move anchor") { moved.toggle() }
      Text("source")
        .frame(width: 8, height: 2, alignment: .topLeading)
        .anchorPreference(key: SetABoundsPreferenceKey.self, value: .bounds) { $0 }
        .offset(x: moved ? 7 : 2, y: moved ? 3 : 1)
        .frame(width: 30, height: 8, alignment: .topLeading)
        .overlayPreferenceValue(SetABoundsPreferenceKey.self, alignment: .topLeading) { anchor in
          GeometryReader { proxy in captureRect(anchor, proxy: proxy, log: log) }
        }
    }
  }
}

@MainActor
private struct SetASwitchingPointAnchor: View {
  let log: SetAPreferenceLog
  @State private var trailing = false
  var body: some View {
    VStack(alignment: .leading) {
      Button("Switch corner") { trailing.toggle() }
      Text("source")
        .frame(width: 12, height: 4)
        .anchorPreference(
          key: SetAPointPreferenceKey.self,
          value: trailing ? AnchorSource<Point>.bottomTrailing : .topLeading
        ) { $0 }
        .overlayPreferenceValue(SetAPointPreferenceKey.self, alignment: .topLeading) { anchor in
          GeometryReader { proxy in capturePoint(anchor, proxy: proxy, log: log) }
        }
    }
  }
}

@MainActor
private struct SetAPreferenceTaskOwner: View {
  let log: SetAPreferenceLog
  @State private var visible = true
  var body: some View {
    VStack(alignment: .leading) {
      Button("Hide task source") { visible = false }
      Text("source")
        .frame(width: 40, height: 3, alignment: .topLeading)
        .preference(key: SetAStringPreferenceKey.self, value: visible ? ["task"] : [])
        .overlayPreferenceValue(SetAStringPreferenceKey.self, alignment: .bottomLeading) { values in
          if !values.isEmpty {
            Text("derived task")
              .task {
                log.taskStarted()
                defer { log.taskFinished() }
                log.events.append("started")
                // Cleanup can also release a task whose runtime handle was lost;
                // only actual cancellation satisfies the cancellation oracle.
                await log.cleanupRelease.wait()
                if Task.isCancelled { log.events.append("cancelled") }
              }
          }
        }
    }
  }
}

@MainActor
private struct SetAFreshDisappear: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  @State private var visible = true
  var body: some View {
    let captured = value
    return VStack(alignment: .leading) {
      Button("Refresh departing") { value += 1 }
      Button("Remove departing") { visible = false }
      if visible {
        Text("departing=\(value)")
          .onDisappear { log.events.append("departed:\(captured)") }
      }
    }
  }
}

@MainActor
private struct SetACoalescedChange: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  var body: some View {
    Button("Write twice") {
      value += 1
      value += 1
    }
    .onChange(of: value) { old, new in log.events.append("\(old)->\(new)") }
  }
}

@MainActor
private struct SetARemountedChange: View {
  let log: SetAPreferenceLog
  @State private var observing = true
  @State private var value = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Toggle change observer") { observing.toggle() }
      Button("Advance change value") { value += 1 }
      if observing {
        Text("observed change=\(value)")
          .onChange(of: value) { old, new in log.events.append("\(old)->\(new)") }
      }
    }
  }
}

@MainActor
private struct SetAAppearInsertion: View {
  let log: SetAPreferenceLog
  @State private var inserted = false
  @State private var unrelated = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Unrelated appearance input") { unrelated += 1 }
      Text("unrelated=\(unrelated)")
      if inserted {
        Text("inserted child").onAppear { log.events.append("child") }
      }
    }
    .onAppear {
      log.events.append("parent")
      inserted = true
    }
  }
}

@MainActor
@Observable
private final class SetAPreferenceObservable {
  var value = 0
}

@MainActor
@Observable
private final class SetAOtherPreferenceObservable {
  var value = 9
}

@MainActor
private struct SetAObservedPreferenceTransform: View {
  let model: SetAPreferenceObservable
  let log: SetAPreferenceLog
  var body: some View {
    Text("observed preference source")
      .preference(key: SetAStringPreferenceKey.self, value: ["base"])
      .transformPreference(SetAStringPreferenceKey.self) { $0.append("observed\(model.value)") }
      .onPreferenceChange(SetAStringPreferenceKey.self) { log.values.append($0) }
  }
}

@MainActor
private struct SetAObservedPreferenceOverlay: View {
  let model: SetAPreferenceObservable
  var body: some View {
    Text("base")
      .frame(width: 50, height: 3, alignment: .topLeading)
      .preference(key: SetAStringPreferenceKey.self, value: ["source"])
      .overlayPreferenceValue(SetAStringPreferenceKey.self, alignment: .bottomLeading) { _ in
        Text("observed-overlay=\(model.value)")
      }
  }
}

@MainActor
private struct SetAEnvironmentModelReader: View {
  @Environment(SetAPreferenceObservable.self) private var model: SetAPreferenceObservable
  var body: some View { Text("model=\(model.value)") }
}

@MainActor
private struct SetATwoEnvironmentModels: View {
  let first: SetAPreferenceObservable
  let replacement: SetAPreferenceObservable
  let other: SetAOtherPreferenceObservable
  @State private var replaced = false
  var body: some View {
    VStack(alignment: .leading) {
      Button("Replace first model") { replaced = true }
      SetATwoEnvironmentModelReader()
        .environment(replaced ? replacement : first)
        .environment(other)
    }
  }
}

@MainActor
private struct SetATwoEnvironmentModelReader: View {
  @Environment(SetAPreferenceObservable.self) private var first: SetAPreferenceObservable
  @Environment(SetAOtherPreferenceObservable.self) private var second: SetAOtherPreferenceObservable
  var body: some View { Text("objects=\(first.value)/\(second.value)") }
}

@MainActor
private struct SetACompletingTask: View {
  let log: SetAPreferenceLog
  @State private var value = 0
  @State private var unrelated = 0
  var body: some View {
    VStack(alignment: .leading) {
      Button("Unrelated task input") { unrelated += 1 }
      Text("unrelated=\(unrelated)")
      Text("completed-value=\(value)")
    }
    .task {
      log.taskStarted()
      defer { log.taskFinished() }
      value = 17
      log.events.append("completed")
    }
  }
}
