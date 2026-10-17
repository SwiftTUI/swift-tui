@_spi(Testing) import SwiftTUITestSupport
// Adversarial set B, pass 3: data flow, state and lifecycle (201–210).
//
// The register fixes the state contract in unusual detail: equal-value writes
// are inert, a closure that outlives its owner reads the authored seed loudly,
// helpers that are not DynamicProperty share a slot and report it, lifecycle
// replacement commits disappearance before appearance, and memoized reuse
// honours a view's own equality. These probes read each rule back through
// the run loop and the snapshot renderer at the seam where the rule is
// enforced: retained values after removal, memo certificates after an equal
// write, namespace keys at dispatch time, slot claims across generic value
// types, task descriptors across reorders, and change observation across
// net no-op writes.
import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Adversarial set B: data flow and lifecycle", .serialized)
struct AdversarialSetBDataFlowTests {
  private func harness<V: View>(
    _ name: String, width: Int = 40, height: Int = 10, @ViewBuilder content: @escaping () -> V
  ) throws -> StressRuntimeHarness<V> {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("SetBDataFlow", name), size: .init(width: width, height: height),
      content: content)
  }

  private func withSeedFallbackTraceSuppressed<Result>(_ body: () throws -> Result) rethrows
    -> Result
  {
    let savedTrace = SoundnessProbeConfiguration.isTraceEnabled
    let savedSeed = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
    let savedMiss = SoundnessProbeConfiguration.stateCaptureMissViolationCount
    SoundnessProbeConfiguration.isTraceEnabled = false
    defer {
      SoundnessProbeConfiguration.isTraceEnabled = savedTrace
      SoundnessProbeConfiguration.stateSeedFallbackViolationCount = savedSeed
      SoundnessProbeConfiguration.stateCaptureMissViolationCount = savedMiss
    }
    return try body()
  }

  // A closure that outlives its owner's committed removal reads the authored
  // seed loudly, whether or not the owner was written to while mounted.
  @Test func setB201ReadAfterRemovalIsLoudEvenAfterPriorWrites() throws {
    let probe = SetBReadProbe()
    let h = try harness("Outlived") { SetBRemovableCounterRoot(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("Increment")
    _ = try h.clickText("Increment")
    try #require(h.frame.contains("Count 2"), "\(h.frame)")
    _ = try h.clickText("Remove")
    try #require(!h.frame.contains("Count"), "\(h.frame)")
    let read = try #require(probe.read)
    withSeedFallbackTraceSuppressed {
      _ = ImperativeRuntimeIssueQueue.drain()
      let seedBefore = SoundnessProbeConfiguration.stateSeedFallbackViolationCount
      let value = read()
      let issues = ImperativeRuntimeIssueQueue.drain()
      withKnownIssue("a removed owner with a prior write hands back its retained value silently") {
        #expect(value == 0, "the authored seed is read, got \(value)")
        #expect(
          issues.contains { $0.code == "state.imperativeSeedFallback" }, "\(issues.map(\.code))")
        #expect(SoundnessProbeConfiguration.stateSeedFallbackViolationCount == seedBefore + 1)
      }
    }
  }

  // An equal-value `@State` write is inert: it neither re-evaluates the owner
  // in the run loop nor invalidates a memoized reuse certificate.
  @Test func setB202EqualValueStateWriteIsInertForMemoReuse() throws {
    let probe = SetBReadProbe()
    let h = try harness("InertWrite") { SetBMemoRoot(probe: probe) }
    defer { h.shutdown() }
    try #require(h.frame.contains("state 7"), "\(h.frame)")
    let evaluations = probe.evaluations
    _ = try h.clickText("Same")
    #expect(probe.evaluations == evaluations, "an equal write re-evaluated the owner")
    _ = try h.clickText("Bump")
    #expect(h.frame.contains("state 8"), "\(h.frame)")
    #expect(probe.evaluations == evaluations + 1)

    let snapshotProbe = SetBReadProbe()
    let root = testIdentity("SetBDataFlow", "MemoSnapshot")
    let renderer = DefaultRenderer()
    defer { withExtendedLifetime(renderer) {} }
    _ = renderer.render(SetBMemoRoot(probe: snapshotProbe), context: .init(identity: root))
    _ = renderer.render(
      SetBMemoRoot(probe: snapshotProbe),
      context: .init(identity: root, invalidatedIdentities: [root]))
    #expect(snapshotProbe.evaluations == 1, "a root re-render reuses the equatable boundary")
    snapshotProbe.binding?.wrappedValue = 7
    _ = renderer.render(
      SetBMemoRoot(probe: snapshotProbe),
      context: .init(identity: root, invalidatedIdentities: [root]))
    #expect(snapshotProbe.evaluations == 1, "evaluations \(snapshotProbe.evaluations)")
  }

  // A `@Namespace` is one stable identifier per instance: the body and an
  // action fired later read the same ID, and two rows read different ones.
  @Test func setB203NamespaceReadsAgreeBetweenBodyAndAction() throws {
    let probe = SetBNamespaceProbe()
    let h = try harness("Namespace") { SetBNamespaceRows(probe: probe) }
    defer { h.shutdown() }
    _ = try h.clickText("ns 0")
    _ = try h.clickText("ns 1")
    #expect(probe.body.count == 2 && probe.action.count == 2, "\(probe.body) \(probe.action)")
    #expect(probe.body[0] != probe.body[1], "rows have distinct namespaces: \(probe.body)")
    withKnownIssue(
      "the dispatch-time authoring context has no structural path, so the action allocates a new namespace"
    ) {
      #expect(probe.action[0] == probe.body[0], "row 0: body \(probe.body) action \(probe.action)")
      #expect(probe.action[1] == probe.body[1], "row 1: body \(probe.body) action \(probe.action)")
    }
  }

  // Two instances of a helper that is not a DynamicProperty share one slot
  // and report `state.duplicateSlotClaim`; they do not trap when their value
  // types differ.
  @Test func setB204DuplicateSlotClaimAcrossValueTypesReportsInsteadOfTrapping() async {
    await withKnownIssue(
      "the second claim on a slot that stores another Value type hits a fatalError"
    ) {
      await #expect(processExitsWith: .success) {
        await MainActor.run {
          let snapshot = DefaultRenderer().render(
            SetBTwoCells(), context: .init(identity: testIdentity("SetBDataFlow", "TwoCells")),
            proposal: .init(width: 20, height: 1))
          let codes = snapshot.diagnostics.runtime.issues.map(\.code)
          #expect(codes.contains("state.duplicateSlotClaim"), "\(codes)")
          #expect(!snapshot.rasterSurface.lines.joined().isEmpty)
        }
      }
    }
  }

  // `.task(id:)` with an unchanged id survives a reorder of its ForEach row:
  // the task is neither cancelled nor restarted.
  @Test func setB205TaskIDSurvivesRowReorder() throws {
    let probe = SetBTaskProbe()
    let h = try harness("TaskReorder") { SetBReorderedTasks(probe: probe) }
    defer { h.shutdown() }
    func descriptors() -> Set<String> {
      Set(h.runLoop.lifecycleCoordinator.activeTaskDescriptors.values.flatMap { $0.map(\.id) })
    }
    try #require(h.activeTaskCount == 2, "\(h.activeTaskCount)")
    let before = descriptors()
    _ = try h.clickText("Reverse")
    try #require(h.frame.contains("row 2") && h.frame.contains("row 1"), "\(h.frame)")
    #expect(h.activeTaskCount == 2, "\(h.activeTaskCount)")
    #expect(
      descriptors() == before, "reorder re-minted task descriptors: \(descriptors()) vs \(before)")
    #expect(h.runLoop.lifecycleCoordinator.taskStartSupersededCount == 0)
    _ = try h.clickText("Prepend")
    #expect(h.activeTaskCount == 3, "\(h.activeTaskCount)")
    #expect(
      descriptors().isSuperset(of: before),
      "a prepended sibling re-minted existing descriptors: \(descriptors())")
  }

  // `onChange` observes committed values: a write that changes and reverts
  // in one action fires nothing, and two writes in one action fire once with
  // the committed pair.
  @Test func setB206OnChangeFiresPerCommittedChange() throws {
    let log = SetBLog()
    let h = try harness("OnChange") { SetBOnChangeFixture(log: log) }
    defer { h.shutdown() }
    _ = try h.clickText("Blip")
    #expect(log.events.isEmpty, "\(log.events)")
    #expect(h.frame.contains("v 0"), "\(h.frame)")
    _ = try h.clickText("Jump")
    #expect(log.events == ["0->2"], "\(log.events)")
    _ = try h.clickText("Jump")
    #expect(
      log.events == ["0->2"], "a write to the same committed value fires nothing: \(log.events)")
    _ = try h.clickText("Blip")
    #expect(log.events == ["0->2", "2->0"], "\(log.events)")
  }

  // Replacement commits the old disappearance before the new appearance, for
  // a branch flip and for an `.id` reset; a double flip in one action commits
  // nothing.
  @Test func setB207ReplacementCommitsDisappearanceBeforeAppearance() throws {
    let log = SetBLog()
    let h = try harness("Lifecycle") { SetBLifecycleFixture(log: log) }
    defer { h.shutdown() }
    try #require(log.events == ["appear A", "appear C"], "\(log.events)")
    log.events.removeAll()
    _ = try h.clickText("Flip")
    #expect(log.events == ["disappear A", "appear B"], "\(log.events)")
    log.events.removeAll()
    _ = try h.clickText("Regen")
    #expect(log.events == ["disappear C", "appear C"], "\(log.events)")
    log.events.removeAll()
    let registrations = h.lifecycleRegistrationCount
    _ = try h.clickText("Double")
    #expect(log.events.isEmpty, "\(log.events)")
    #expect(h.lifecycleRegistrationCount == registrations)
    #expect(h.frame.contains("B body"), "\(h.frame)")
  }

  // A `@State` initial value is read once at mount; a changed init argument
  // is ignored until the identity changes.
  @Test func setB208StateInitialValueIsReadOnceUntilIdentityChanges() throws {
    let h = try harness("Seeded") { SetBSeededRoot() }
    defer { h.shutdown() }
    try #require(h.frame.contains("plain 1") && h.frame.contains("keyed 1"), "\(h.frame)")
    _ = try h.clickText("Advance")
    #expect(h.frame.contains("plain 1"), "the mounted seed is kept: \(h.frame)")
    #expect(h.frame.contains("keyed 11"), "the .id reset re-seeds: \(h.frame)")
    _ = try h.clickText("plain +")
    #expect(h.frame.contains("plain 2"), "\(h.frame)")
    _ = try h.clickText("Advance")
    #expect(h.frame.contains("plain 2"), "\(h.frame)")
    #expect(h.frame.contains("keyed 21"), "\(h.frame)")
  }

  // `.equatable()` makes the view's own `==` the reuse contract: a field the
  // comparison ignores never re-evaluates the body, a compared field does, and
  // a sibling holding a closure recomputes on every parent evaluation.
  @Test func setB209EquatableViewsReuseByTheirOwnEquality() throws {
    let chrome = SetBReadProbe()
    let closure = SetBReadProbe()
    let h = try harness("Equatable") { SetBEquatableRoot(chrome: chrome, closure: closure) }
    defer { h.shutdown() }
    try #require(h.frame.contains("a 0"), "\(h.frame)")
    #expect(chrome.evaluations == 1)
    // Initial focus adoption can resolve the unguarded closure sibling again.
    let initialClosureEvaluations = closure.evaluations
    #expect(initialClosureEvaluations >= 1)
    _ = try h.clickText("Extra")
    #expect(h.frame.contains("a 0"), "the ignored field leaves the body stale: \(h.frame)")
    #expect(chrome.evaluations == 1, "\(chrome.evaluations)")
    #expect(
      closure.evaluations == initialClosureEvaluations + 1,
      "a closure-holding sibling recomputes: \(closure.evaluations)")
    _ = try h.clickText("Title")
    #expect(h.frame.contains("b 1"), "\(h.frame)")
    #expect(chrome.evaluations == 2, "\(chrome.evaluations)")
  }

  // Mounting a view with a `@Namespace` evaluates its body once.
  @Test func setB210NamespaceMountEvaluatesTheBodyOnce() throws {
    let probe = SetBReadProbe()
    let h = try harness("NamespaceMount") { SetBNamespaceHolder(probe: probe) }
    defer { h.shutdown() }
    try #require(h.frame.contains("holder"), "\(h.frame)")
    withKnownIssue(
      "the first namespace read writes state during body and schedules a second evaluation"
    ) {
      #expect(probe.evaluations == 1, "evaluations \(probe.evaluations)")
    }
    let settled = probe.evaluations
    _ = try h.renderAfterExternalMutation()
    #expect(probe.evaluations == settled + 1, "\(probe.evaluations)")
  }
}

@MainActor
private final class SetBReadProbe {
  var evaluations = 0
  var read: (() -> Int)?
  var binding: Binding<Int>?
}

@MainActor
private final class SetBNamespaceProbe {
  var body: [Int: UInt64] = [:]
  var action: [Int: UInt64] = [:]
}

@MainActor
private final class SetBTaskProbe {
  var starts = 0
}

@MainActor
private final class SetBLog {
  var events: [String] = []
}

@MainActor
private struct SetBRemovableCounterRoot: View {
  let probe: SetBReadProbe
  @State private var show = true

  var body: some View {
    VStack(alignment: .leading) {
      if show {
        SetBRemovableCounter(probe: probe)
      }
      Button("Remove") { show = false }
    }
  }
}

@MainActor
private struct SetBRemovableCounter: View {
  let probe: SetBReadProbe
  @State private var count = 0

  var body: some View {
    probe.read = { count }
    return VStack(alignment: .leading) {
      Text("Count \(count)")
      Button("Increment") { count += 1 }
    }
  }
}

@MainActor
private struct SetBMemoRoot: View {
  let probe: SetBReadProbe
  @State private var nonce = 0

  var body: some View {
    VStack(alignment: .leading) {
      SetBMemoBoundary(probe: probe, nonce: nonce).equatable()
      Button("Same") { probe.binding?.wrappedValue = probe.binding?.wrappedValue ?? 7 }
      Button("Bump") { probe.binding?.wrappedValue += 1 }
    }
  }
}

@MainActor
private struct SetBMemoBoundary: View, Equatable {
  let probe: SetBReadProbe
  let nonce: Int
  @State private var value = 7

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.nonce == rhs.nonce }

  var body: some View {
    probe.evaluations += 1
    probe.binding = $value
    return Text("state \(value)")
  }
}

@MainActor
private struct SetBNamespaceRows: View {
  let probe: SetBNamespaceProbe

  var body: some View {
    VStack(alignment: .leading) {
      ForEach(0..<2, id: \.self) { index in
        SetBNamespaceRow(index: index, probe: probe)
      }
    }
  }
}

@MainActor
private struct SetBNamespaceRow: View {
  let index: Int
  let probe: SetBNamespaceProbe
  @Namespace private var namespace

  var body: some View {
    probe.body[index] = namespace.rawValue
    return Button("ns \(index)") { probe.action[index] = namespace.rawValue }
  }
}

@MainActor
private struct SetBCell<Value> {
  @State var value: Value

  init(value: Value) {
    _value = State(initialValue: value)
  }
}

@MainActor
private struct SetBTwoCells: View {
  var number = SetBCell(value: 1)
  var text = SetBCell(value: "x")

  var body: some View {
    Text("\(number.value) \(text.value)")
  }
}

@MainActor
private struct SetBReorderedTasks: View {
  let probe: SetBTaskProbe
  @State private var order = [1, 2]

  var body: some View {
    VStack(alignment: .leading) {
      ForEach(order, id: \.self) { row in
        Text("row \(row)")
          .task(id: "k") {
            probe.starts += 1
            await suspendUntilCancelled()
          }
      }
      Button("Reverse") { order.reverse() }
      Button("Prepend") { order.insert(9, at: 0) }
    }
  }
}

@MainActor
private struct SetBOnChangeFixture: View {
  let log: SetBLog
  @State private var v = 0

  var body: some View {
    VStack(alignment: .leading) {
      Text("v \(v)").onChange(of: v) { old, new in log.events.append("\(old)->\(new)") }
      Button("Blip") {
        v = 1
        v = 0
      }
      Button("Jump") {
        v = 1
        v = 2
      }
    }
  }
}

@MainActor
private struct SetBLifecycleFixture: View {
  let log: SetBLog
  @State private var flag = true
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading) {
      if flag {
        Text("A body").onAppear { log.events.append("appear A") }
          .onDisappear { log.events.append("disappear A") }
      } else {
        Text("B body").onAppear { log.events.append("appear B") }
          .onDisappear { log.events.append("disappear B") }
      }
      Text("C body").onAppear { log.events.append("appear C") }
        .onDisappear { log.events.append("disappear C") }
        .id(generation)
      Button("Flip") { flag.toggle() }
      Button("Regen") { generation += 1 }
      Button("Double") {
        flag.toggle()
        flag.toggle()
      }
    }
  }
}

@MainActor
private struct SetBSeeded: View {
  let label: String
  @State private var count: Int

  init(label: String, start: Int) {
    self.label = label
    _count = State(initialValue: start)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("\(label) \(count)")
      Button("\(label) +") { count += 1 }
    }
  }
}

@MainActor
private struct SetBSeededRoot: View {
  @State private var n = 1

  var body: some View {
    VStack(alignment: .leading) {
      SetBSeeded(label: "plain", start: n)
      SetBSeeded(label: "keyed", start: n).id(n)
      Button("Advance") { n += 10 }
    }
  }
}

@MainActor
private struct SetBEquatableRoot: View {
  let chrome: SetBReadProbe
  let closure: SetBReadProbe
  @State private var title = "a"
  @State private var extra = 0

  var body: some View {
    VStack(alignment: .leading) {
      SetBChrome(title: title, extra: extra, probe: chrome).equatable()
      SetBClosureHolder(probe: closure, action: {})
      Button("Extra") { extra += 1 }
      Button("Title") { title = "b" }
    }
  }
}

@MainActor
private struct SetBChrome: View, Equatable {
  let title: String
  let extra: Int
  let probe: SetBReadProbe

  nonisolated static func == (lhs: Self, rhs: Self) -> Bool { lhs.title == rhs.title }

  var body: some View {
    probe.evaluations += 1
    return Text("\(title) \(extra)")
  }
}

@MainActor
private struct SetBClosureHolder: View {
  let probe: SetBReadProbe
  let action: @MainActor @Sendable () -> Void

  var body: some View {
    probe.evaluations += 1
    return Text("closure")
  }
}

@MainActor
private struct SetBNamespaceHolder: View {
  let probe: SetBReadProbe
  @Namespace private var namespace

  var body: some View {
    probe.evaluations += 1
    return Text("holder \(namespace.rawValue > 0 ? "on" : "off")")
  }
}
