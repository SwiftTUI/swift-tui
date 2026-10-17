@_spi(Testing) import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized, FailOnSoundnessViolationGrowth(), .timeLimit(.minutes(1)))
struct AdversarialSetAStateTests {
  @Test func setA101KeyedRotationKeepsUnequalLocalValuesWithTheirOwners() throws {
    let h = try counters()
    defer { h.shutdown() }
    try h.clickText("Add A")
    try #require(
      counter("A", in: h) == 1, "Initial click must mutate A before rotation: \(h.frame)")
    try h.clickText("Add A")
    try #require(counter("A", in: h) == 2, "Second click must retain A's first write: \(h.frame)")
    try h.clickText("Add B")
    try #require(counter("A", in: h) == 2 && counter("B", in: h) == 1, "\(h.frame)")
    for _ in 0..<3 {
      try command("r", in: h)
      #expect(counter("A", in: h) == 2, "\(h.frame)")
      #expect(counter("B", in: h) == 1, "\(h.frame)")
      #expect(counter("C", in: h) == 0, "\(h.frame)")
    }
  }

  @Test func setA102RemovedKeyStartsFreshWhileItsSurvivingSiblingKeepsState() throws {
    let h = try counters()
    defer { h.shutdown() }
    try h.clickText("Add A")
    try h.clickText("Add B")
    try #require(counter("A", in: h) == 1 && counter("B", in: h) == 1, "\(h.frame)")
    try command("d", in: h)
    #expect(!h.frame.contains("Add A"))
    try command("d", in: h)
    #expect(counter("A", in: h) == 0, "\(h.frame)")
    #expect(counter("B", in: h) == 1, "\(h.frame)")
  }

  @Test func setA103LeadingInsertionCannotCopyStateIntoTheNewKey() throws {
    let h = try counters()
    defer { h.shutdown() }
    try h.clickText("Add A")
    try h.clickText("Add C")
    try #require(counter("A", in: h) == 1 && counter("C", in: h) == 1, "\(h.frame)")
    try command("i", in: h)
    #expect(counter("Z", in: h) == 0, "\(h.frame)")
    #expect(counter("A", in: h) == 1, "\(h.frame)")
    #expect(counter("C", in: h) == 1, "\(h.frame)")
    try h.clickText("Add Z")
    #expect(counter("Z", in: h) == 1, "\(h.frame)")
    #expect(counter("A", in: h) == 1, "\(h.frame)")
  }

  @Test func setA104ExplicitIdentityPreservesCounterActionsAndState() throws {
    let probe = SetACounterProbe()
    let h = try counters(explicitIdentity: true, probe: probe)
    defer { h.shutdown() }
    try h.clickText("Add A")
    #expect(probe.events == ["A:0->1"], "Pointer action events: \(probe.events)")
    withKnownIssue("STUI-959: explicit identity loses a dispatched pointer action's state write") {
      #expect(counter("A", in: h) == 1, "\(h.frame)")
    }
    try h.focusText("Add B")
    try h.pressKey(.init(.return))
    #expect(probe.events == ["A:0->1", "B:0->1"], "All action events: \(probe.events)")
    withKnownIssue("STUI-959: explicit identity loses a dispatched keyboard action's state write") {
      #expect(counter("B", in: h) == 1, "\(h.frame)")
    }
  }

  @Test func setA105ChangedInitialValuesSeedOnlyNewOwners() throws {
    let h = try counters()
    defer { h.shutdown() }
    try h.clickText("Add A")
    try #require(counter("A", in: h) == 1 && counter("B", in: h) == 0, "\(h.frame)")
    try command("s", in: h)
    #expect(counter("A", in: h) == 1, "\(h.frame)")
    #expect(counter("B", in: h) == 0, "\(h.frame)")
    try command("i", in: h)
    #expect(counter("Z", in: h) == 10, "\(h.frame)")
    try command("d", in: h)
    try command("d", in: h)
    #expect(counter("A", in: h) == 10, "\(h.frame)")
    #expect(counter("B", in: h) == 0, "\(h.frame)")
  }

  @Test func setA106FlattenedRowsKeepTwoSameTypedStateSlotsDistinctAfterRotation() throws {
    let h = try make("106") { SetAFlattenedCounters() }
    defer { h.shutdown() }
    try h.clickText("Add AL")
    try h.clickText("Add BR")
    try h.clickText("Add BR")
    try command("r", in: h)
    #expect(h.frame.contains("AL=1"))
    #expect(h.frame.contains("AR=0"))
    #expect(h.frame.contains("BL=0"))
    #expect(h.frame.contains("BR=2"))
  }

  @Test func setA107NestedRepeatedKeysStayScopedToTheirParentAfterBothReorders() throws {
    let h = try make("107") { SetANestedCounters() }
    defer { h.shutdown() }
    try h.clickText("Add X0")
    try h.clickText("Add Y1")
    try h.clickText("Add Y1")
    try command("p", in: h)
    try command("r", in: h)
    #expect(h.frame.contains("X0=1"))
    #expect(h.frame.contains("X1=0"))
    #expect(h.frame.contains("Y0=0"))
    #expect(h.frame.contains("Y1=2"))
  }

  @Test func setA108EnvironmentWritersFollowKeyedOwnersAcrossOrderAndValueChanges() throws {
    let h = try environment()
    defer { h.shutdown() }
    try command("r", in: h)
    try command("g", in: h)
    #expect(h.frame.contains("A:token-A-1"))
    #expect(h.frame.contains("B:token-B-1"))
    #expect(h.frame.contains("outer:outer-1"))
  }

  @Test func setA109ExplicitNilEnvironmentDoesNotRevealAnOuterOptionalValue() throws {
    let h = try environment()
    defer { h.shutdown() }
    try command("n", in: h)
    try command("g", in: h)
    #expect(h.frame.contains("masked:nil"))
    #expect(h.frame.contains("outer:outer-1"))
    try command("n", in: h)
    #expect(h.frame.contains("masked:inner-1"))
  }

  @Test func setA110EnvironmentTransformUsesTheLatestParentValueExactlyOnce() throws {
    let h = try environment()
    defer { h.shutdown() }
    for generation in 1...3 {
      try command("g", in: h)
      #expect(h.frame.contains("transformed:outer-\(generation)/suffix"))
      #expect(!h.frame.contains("/suffix/suffix"))
    }
  }

  @Test func setA111RetainedActionReadsItsCurrentEnvironmentAfterSiblingReorder() throws {
    let h = try environment()
    defer { h.shutdown() }
    try h.clickText("Read A")
    #expect(h.frame.contains("read=token-A-0"))
    try command("g", in: h)
    try command("r", in: h)
    try h.clickText("Read A")
    #expect(h.frame.contains("read=token-A-1"))
    try h.clickText("Read B")
    #expect(h.frame.contains("read=token-B-1"))
  }

  @Test func setA112EnvironmentMutationCannotOverwriteReaderLocalState() throws {
    let h = try environment()
    defer { h.shutdown() }
    try h.clickText("Read A")
    try h.clickText("Read A")
    try command("g", in: h)
    try command("r", in: h)
    #expect(h.frame.contains("A:token-A-1 taps=2"))
    #expect(h.frame.contains("B:token-B-1 taps=0"))
  }

  @Test func setA113EqualAdjacentPathValuesStillCreateDistinctDestinationOwners() throws {
    let h = try path()
    defer { h.shutdown() }
    try h.clickText("Open path")
    try h.clickText("Add route")
    try command("a", in: h)
    #expect(h.frame.contains("route=1 local=0"))
    #expect(h.frame.contains("depth=2"))
  }

  @Test func setA114ReplacingTopPathValueStartsFreshLocalState() throws {
    let h = try path()
    defer { h.shutdown() }
    try h.clickText("Open path")
    try h.clickText("Add route")
    try command("v", in: h)
    #expect(h.frame.contains("route=2 local=0"))
    #expect(h.frame.contains("depth=1"))
  }

  @Test func setA115PoppedPathValueCannotResurrectItsPreviousLocalState() throws {
    let h = try path()
    defer { h.shutdown() }
    try h.clickText("Open path")
    try command("a", in: h)
    try h.clickText("Add route")
    try command("p", in: h)
    try command("a", in: h)
    #expect(h.frame.contains("route=1 local=0"))
    #expect(h.frame.contains("depth=2"))
  }

  @Test func setA116SiblingBooleanProjectionsNameDifferentNavigationLifetimes() throws {
    let h = try projectedNavigation(item: false)
    defer { h.shutdown() }
    try h.clickText("Add destination")
    try #require(h.frame.contains("source=A local=1"), "\(h.frame)")
    try h.clickText("Switch source")
    withKnownIssue(
      "STUI-956: member-projected Boolean bindings lose navigation declaration identity"
    ) {
      #expect(h.frame.contains("source=B local=0"))
    }
    try h.clickText("Add destination")
    try h.clickText("Switch source")
    withKnownIssue(
      "STUI-956: member-projected Boolean bindings reuse the departing destination's state"
    ) {
      #expect(h.frame.contains("source=A local=0"))
    }
  }

  @Test func setA117ProjectedDestinationPopWritesOnlyTheCurrentlyPresentedField() throws {
    let h = try projectedNavigation(item: false)
    defer { h.shutdown() }
    try h.clickText("Switch source")
    try h.focusText("Add destination")
    try h.pressKey(.init(.escape))
    #expect(h.frame.contains("flags=true,false"))
    #expect(h.frame.contains("Root source"))
  }

  @Test func setA118SiblingItemProjectionsWithEqualIDsHaveSeparateLocalState() throws {
    let h = try projectedNavigation(item: true)
    defer { h.shutdown() }
    try h.clickText("Add destination")
    try #require(h.frame.contains("source=A local=1"), "\(h.frame)")
    try h.clickText("Switch source")
    withKnownIssue("STUI-956: member-projected item bindings lose navigation declaration identity")
    {
      #expect(h.frame.contains("source=B local=0"))
    }
    try h.clickText("Add destination")
    try h.clickText("Switch source")
    withKnownIssue(
      "STUI-956: member-projected item bindings reuse the departing destination's state"
    ) {
      #expect(h.frame.contains("source=A local=0"))
    }
  }

  @Test func setA119PathEscapeAfterReplacementPopsOnlyTheCurrentTop() throws {
    let h = try path()
    defer { h.shutdown() }
    try h.clickText("Open path")
    try command("a", in: h)
    try command("v", in: h)
    try h.focusText("Add route")
    try h.pressKey(.init(.escape))
    #expect(h.frame.contains("depth=1"))
    #expect(h.frame.contains("route=1"))
    try h.focusText("Add route")
    try h.pressKey(.init(.escape))
    #expect(h.frame.contains("depth=0"))
    #expect(h.frame.contains("Open path"))
  }

  @Test func setA120UnrelatedInputMutationDoesNotRestartStableTasks() async throws {
    let probe = SetATaskProbe()
    let h = try tasks(probe)
    defer { h.shutdown() }
    try await awaitEvents(probe, count: 2)
    try command("u", in: h)
    #expect(h.frame.contains("unrelated=1"))
    #expect(h.activeTaskCount == 2)
    h.shutdown()
    try await awaitEvents(probe, count: 4)
    #expect(probe.events.sorted() == ["end:A:0", "end:B:0", "start:A:0", "start:B:0"])
  }

  @Test func setA121TaskIDReplacementCancelsEachOldOwnerAndStartsEachNewOwner() async throws {
    let probe = SetATaskProbe()
    let h = try tasks(probe)
    defer { h.shutdown() }
    try await awaitEvents(probe, count: 2)
    try command("g", in: h)
    try await awaitEvents(probe, count: 6)
    #expect(Set(probe.events.suffix(4)) == ["end:A:0", "end:B:0", "start:A:1", "start:B:1"])
    #expect(h.activeTaskCount == 2)
  }

  @Test func setA122KeyedTaskReorderDoesNotCancelSurvivingTasks() async throws {
    let probe = SetATaskProbe()
    let h = try tasks(probe)
    defer { h.shutdown() }
    try await awaitEvents(probe, count: 2)
    try command("r", in: h)
    try command("g", in: h)
    try await awaitEvents(probe, count: 6)
    #expect(probe.events.filter { $0 == "start:A:0" }.count == 1)
    #expect(probe.events.filter { $0 == "start:B:0" }.count == 1)
    #expect(probe.events.filter { $0 == "end:A:0" }.count == 1)
    #expect(probe.events.filter { $0 == "end:B:0" }.count == 1)
    #expect(h.activeTaskCount == 2)
  }

  @Test func setA123RemovingAndRestoringOneTaskOwnerLeavesItsPeerRunning() async throws {
    let probe = SetATaskProbe()
    let h = try tasks(probe)
    defer { h.shutdown() }
    try await awaitEvents(probe, count: 2)
    try command("d", in: h)
    try await awaitEvents(probe, count: 3)
    #expect(probe.events.last == "end:A:0")
    #expect(h.activeTaskCount == 1)
    try command("d", in: h)
    try await awaitEvents(probe, count: 4)
    #expect(probe.events.last == "start:A:0")
    #expect(!probe.events.contains("end:B:0"))
    #expect(h.activeTaskCount == 2)
  }

  @Test func setA124EqualTaskIDsOnOneNodeStillHaveIndependentModifierOwnership() async throws {
    let probe = SetATaskProbe()
    let h = try make("124") { SetATwinTasks(probe: probe) }
    defer { h.shutdown() }
    try await awaitEvents(probe, count: 2)
    #expect(Set(probe.events) == ["start:first:0", "start:second:0"])
    try command("g", in: h)
    try await awaitEvents(probe, count: 4)
    #expect(Set(probe.events.suffix(2)) == ["end:first:0", "start:first:1"])
    #expect(h.activeTaskCount == 2)
  }

  @Test func setA125ShuttingDownOneGraphCannotCancelAnotherGraphsMatchingTasks() async throws {
    let firstProbe = SetATaskProbe()
    let secondProbe = SetATaskProbe()
    let first = try tasks(firstProbe)
    let second = try tasks(secondProbe)
    defer {
      first.shutdown()
      second.shutdown()
    }
    try await awaitEvents(firstProbe, count: 2)
    try await awaitEvents(secondProbe, count: 2)
    first.shutdown()
    try await awaitEvents(firstProbe, count: 4)
    try command("g", in: second)
    try await awaitEvents(secondProbe, count: 6)
    #expect(first.activeTaskCount == 0)
    #expect(second.activeTaskCount == 2)
    #expect(
      Set(secondProbe.events.suffix(4)) == [
        "end:A:0", "end:B:0", "start:A:1", "start:B:1",
      ])
  }

  private func make<V: View>(_ name: String, @ViewBuilder content: @escaping () -> V) throws
    -> StressRuntimeHarness<V>
  {
    try StressRuntimeHarness(
      rootIdentity: testIdentity("AdversarialSetAState", name),
      size: .init(width: 64, height: 24), content: content)
  }

  private func counters(explicitIdentity: Bool = false, probe: SetACounterProbe? = nil) throws
    -> StressRuntimeHarness<SetAKeyedCounters>
  {
    try make("counters") { SetAKeyedCounters(explicitIdentity: explicitIdentity, probe: probe) }
  }

  private func counter<V: View>(_ label: String, in h: StressRuntimeHarness<V>) -> Int? {
    let prefix = "\(label)="
    return h.frame.split(whereSeparator: \.isWhitespace)
      .first { $0.hasPrefix(prefix) }
      .flatMap { Int($0.dropFirst(prefix.count)) }
  }

  private func environment() throws -> StressRuntimeHarness<SetAEnvironmentRoot> {
    try make("environment") { SetAEnvironmentRoot() }
  }

  private func path() throws -> StressRuntimeHarness<SetAPathRoot> {
    try make("path") { SetAPathRoot() }
  }

  private func projectedNavigation(item: Bool) throws -> StressRuntimeHarness<
    SetAProjectedNavigation
  > {
    try make("projected-navigation") { SetAProjectedNavigation(usesItem: item) }
  }

  private func tasks(_ probe: SetATaskProbe) throws -> StressRuntimeHarness<SetATaskRoot> {
    try make("tasks") { SetATaskRoot(probe: probe) }
  }

  private func command<V: View>(_ key: Character, in h: StressRuntimeHarness<V>) throws {
    try h.pressKey(.init(.character(key), modifiers: .ctrl))
  }

  private func awaitEvents(_ probe: SetATaskProbe, count: Int) async throws {
    try await waitUntil(
      "Set A task events", lastObservation: { "\(probe.events)" },
      condition: { probe.events.count >= count })
    #expect(probe.events.count == count, "\(probe.events)")
  }
}

@MainActor
private final class SetACounterProbe {
  var events: [String] = []
}

@MainActor
private struct SetACounter: View {
  let label: String
  let probe: SetACounterProbe?
  @State private var count: Int

  init(_ label: String, seed: Int = 0, probe: SetACounterProbe? = nil) {
    self.label = label
    self.probe = probe
    _count = State(initialValue: seed)
  }

  var body: some View {
    HStack(spacing: 1) {
      Button("Add \(label)") {
        let before = count
        count += 1
        probe?.events.append("\(label):\(before)->\(count)")
      }
      Text("\(label)=\(count)")
    }
  }
}

@MainActor
private struct SetAKeyedCounters: View {
  let explicitIdentity: Bool
  let probe: SetACounterProbe?
  @State private var keys = ["A", "B", "C"]
  @State private var seed = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(keys, id: \.self) { key in
        if explicitIdentity {
          SetACounter(key, seed: seed, probe: probe).id("counter-\(key)")
        } else {
          SetACounter(key, seed: seed, probe: probe)
        }
      }
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      let first = keys.removeFirst()
      keys.append(first)
      return .handled
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      if keys.contains("A") { keys.removeAll { $0 == "A" } } else { keys.append("A") }
      return .handled
    }
    .onKeyPress(.character("i"), modifiers: .ctrl) { _ in
      keys.insert("Z", at: 0)
      return .handled
    }
    .onKeyPress(.character("s"), modifiers: .ctrl) { _ in
      seed += 10
      return .handled
    }
  }
}

@MainActor
private struct SetAFlattenedCounters: View {
  @State private var reversed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(reversed ? ["B", "A"] : ["A", "B"], id: \.self) { key in
        Group {
          SetACounter("\(key)L")
          SetACounter("\(key)R")
        }
      }
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      reversed.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetANestedCounters: View {
  @State private var parentsReversed = false
  @State private var childrenReversed = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(parentsReversed ? ["Y", "X"] : ["X", "Y"], id: \.self) { parent in
        VStack(alignment: .leading, spacing: 0) {
          ForEach(childrenReversed ? [1, 0] : [0, 1], id: \.self) { child in
            SetACounter("\(parent)\(child)")
          }
        }
      }
    }
    .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
      parentsReversed.toggle()
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      childrenReversed.toggle()
      return .handled
    }
  }
}

private enum SetAStateTokenKey: EnvironmentKey {
  static let defaultValue: String? = "default"
}

extension EnvironmentValues {
  var setAStateToken: String? {
    get { self[SetAStateTokenKey.self] }
    set { self[SetAStateTokenKey.self] = newValue }
  }
}

@MainActor
private struct SetAEnvironmentReader: View {
  let label: String
  @Binding var lastRead: String
  @Environment(\.setAStateToken) private var token
  @State private var taps = 0
  var body: some View {
    HStack(spacing: 1) {
      Text("\(label):\(token ?? "nil") taps=\(taps)")
      Button("Read \(label)") {
        lastRead = token ?? "nil"
        taps += 1
      }
    }
  }
}

@MainActor
private struct SetAEnvironmentRoot: View {
  @State private var generation = 0
  @State private var reversed = false
  @State private var masked = false
  @State private var lastRead = "none"
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      ForEach(reversed ? ["B", "A"] : ["A", "B"], id: \.self) { key in
        SetAEnvironmentReader(label: key, lastRead: $lastRead)
          .environment(\.setAStateToken, "token-\(key)-\(generation)")
      }
      SetAEnvironmentReader(label: "outer", lastRead: $lastRead)
      SetAEnvironmentReader(label: "masked", lastRead: $lastRead)
        .environment(\.setAStateToken, masked ? nil : "inner-\(generation)")
      SetAEnvironmentReader(label: "transformed", lastRead: $lastRead)
        .transformEnvironment(\.setAStateToken) { $0 = ($0 ?? "nil") + "/suffix" }
      Text("read=\(lastRead)")
    }
    .environment(\.setAStateToken, "outer-\(generation)")
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      generation += 1
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      reversed.toggle()
      return .handled
    }
    .onKeyPress(.character("n"), modifiers: .ctrl) { _ in
      masked.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetAPathDestination: View {
  let value: Int
  @State private var local = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("route=\(value) local=\(local)")
      Button("Add route") { local += 1 }
    }
  }
}

@MainActor
private struct SetAPathRoot: View {
  @State private var path: [Int] = []
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("depth=\(path.count)")
      NavigationStack(path: $path) {
        Button("Open path") { path = [1] }
          .navigationDestination(for: Int.self) { value in SetAPathDestination(value: value) }
      }
    }
    .onKeyPress(.character("a"), modifiers: .ctrl) { _ in
      path.append(1)
      return .handled
    }
    .onKeyPress(.character("v"), modifiers: .ctrl) { _ in
      if !path.isEmpty { path[path.count - 1] = 2 }
      return .handled
    }
    .onKeyPress(.character("p"), modifiers: .ctrl) { _ in
      if !path.isEmpty { path.removeLast() }
      return .handled
    }
  }
}

private struct SetAPresentationItem: Identifiable, Sendable {
  let id = "same"
}

private struct SetAPresentationFields: Sendable {
  var first = true
  var second = true
  var firstItem: SetAPresentationItem? = .init()
  var secondItem: SetAPresentationItem? = .init()
}

@MainActor
private struct SetAProjectedNavigation: View {
  let usesItem: Bool
  @State private var fields = SetAPresentationFields()
  @State private var second = false
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("flags=\(fields.first),\(fields.second)")
      NavigationStack {
        if usesItem {
          if second {
            source.navigationDestination(item: $fields.secondItem) { _ in destination }
          } else {
            source.navigationDestination(item: $fields.firstItem) { _ in destination }
          }
        } else {
          if second {
            source.navigationDestination(isPresented: $fields.second) { destination }
          } else {
            source.navigationDestination(isPresented: $fields.first) { destination }
          }
        }
      }
    }
  }

  private var source: some View { Text("Root source").id("projected-source") }
  private var destination: some View {
    SetAProjectedDestination(label: second ? "B" : "A") { second.toggle() }
  }
}

@MainActor
private struct SetAProjectedDestination: View {
  let label: String
  let switchSource: @MainActor () -> Void
  @State private var local = 0
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("source=\(label) local=\(local)")
      Button("Add destination") { local += 1 }
      Button("Switch source", action: switchSource)
    }
  }
}

@MainActor
private final class SetATaskProbe {
  var events: [String] = []
  func run(_ key: String, generation: Int) async {
    events.append("start:\(key):\(generation)")
    await suspendUntilCancelled()
    events.append("end:\(key):\(generation)")
  }
}

@MainActor
private struct SetATaskRoot: View {
  let probe: SetATaskProbe
  @State private var generation = 0
  @State private var unrelated = 0
  @State private var reversed = false
  @State private var hidesA = false
  var body: some View {
    let current = generation
    let keys = (reversed ? ["B", "A"] : ["A", "B"]).filter { !hidesA || $0 != "A" }
    VStack(alignment: .leading, spacing: 0) {
      Button("Keep focus") {}
      Text("unrelated=\(unrelated)")
      ForEach(keys, id: \.self) { key in
        Text("task \(key) generation \(current)")
          .task(id: current) { await probe.run(key, generation: current) }
      }
    }
    .onKeyPress(.character("u"), modifiers: .ctrl) { _ in
      unrelated += 1
      return .handled
    }
    .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
      generation += 1
      return .handled
    }
    .onKeyPress(.character("r"), modifiers: .ctrl) { _ in
      reversed.toggle()
      return .handled
    }
    .onKeyPress(.character("d"), modifiers: .ctrl) { _ in
      hidesA.toggle()
      return .handled
    }
  }
}

@MainActor
private struct SetATwinTasks: View {
  let probe: SetATaskProbe
  @State private var generation = 0
  var body: some View {
    let current = generation
    Button("Tasks") {}
      .task(id: current) { await probe.run("first", generation: current) }
      .task(id: 0) { await probe.run("second", generation: 0) }
      .onKeyPress(.character("g"), modifiers: .ctrl) { _ in
        generation += 1
        return .handled
      }
  }
}
