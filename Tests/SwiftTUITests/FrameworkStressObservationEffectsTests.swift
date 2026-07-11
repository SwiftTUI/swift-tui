import Observation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite(.serialized)
struct FrameworkStressObservationEffectsTests {}

// MARK: - Attempt 001: conditional observable-property dependency switching

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 001 conditional dependency follows the selected property")
  func observationEffects001ConditionalDependencyFollowsSelectedProperty() throws {
    // Hypothesis: the observation bridge may retain the property subscription
    // from the prior conditional path and fail to arm the newly selected one.
    let model = ObservationEffects001Model()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects001"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects001View(model: model)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      model.primary = generation
      var frame = try harness.render()
      #expect(frame.contains("001 primary \(generation)"))

      model.usesPrimary = false
      frame = try harness.render()
      #expect(frame.contains("001 secondary \(generation - 1)"))

      model.primary = generation + 100
      frame = try harness.render()
      #expect(frame.contains("001 secondary \(generation - 1)"))

      model.secondary = generation
      frame = try harness.render()
      #expect(frame.contains("001 secondary \(generation)"))

      model.usesPrimary = true
      frame = try harness.render()
      #expect(frame.contains("001 primary \(generation + 100)"))
    }
  }
}

@Observable
private final class ObservationEffects001Model {
  var usesPrimary = true
  var primary = 0
  var secondary = 0
}

@MainActor
private struct ObservationEffects001View: View {
  let model: ObservationEffects001Model

  var body: some View {
    Text(
      model.usesPrimary
        ? "001 primary \(model.primary)"
        : "001 secondary \(model.secondary)"
    )
  }
}

// MARK: - Attempt 002: nested computed observable dependency switching

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 002 nested computed dependency re-arms its backing read")
  func observationEffects002NestedComputedDependencyRearmsBackingRead() throws {
    // Hypothesis: a computed property reached through a nested observable can
    // leave the bridge armed for the backing field from its first branch.
    let model = ObservationEffects002Model()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects002"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects002View(model: model)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      model.child.usesFirst.toggle()
      if model.child.usesFirst {
        model.child.first = generation
      } else {
        model.child.second = generation
      }
      let frame = try harness.render()
      #expect(frame.contains("002 \(generation)"))
    }
  }
}

private struct ObservationEffects002View: View {
  let model: ObservationEffects002Model

  var body: some View {
    Text("002 \(model.child.selectedValue)")
  }
}

@Observable
private final class ObservationEffects002Model {
  var child = ObservationEffects002Child()
}

@Observable
private final class ObservationEffects002Child {
  var usesFirst = true
  var first = 0
  var second = 0

  var selectedValue: Int {
    usesFirst ? first : second
  }
}

// MARK: - Attempt 003: duplicate observable readers

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 003 duplicate readers both receive each observed mutation")
  func observationEffects003DuplicateReadersBothReceiveObservedMutation() throws {
    // Hypothesis: two ViewNodeIDs reading the same registrar property may be
    // collapsed by identity-keyed observation bookkeeping.
    let model = ObservationEffects003Model()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects003"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects003View(model: model)
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      model.value = generation
      let frame = try harness.render()
      #expect(frame.contains("003 first \(generation)"))
      #expect(frame.contains("003 second \(generation)"))
    }
  }
}

private struct ObservationEffects003View: View {
  let model: ObservationEffects003Model

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("003 first \(model.value)").id("observation-effects-003-first")
      Text("003 second \(model.value)").id("observation-effects-003-second")
    }
  }
}

@Observable
private final class ObservationEffects003Model {
  var value = 0
}

// MARK: - Attempt 004: stable reader model replacement

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 004 a replaced model drops the retired observation callback")
  func observationEffects004ReplacedModelDropsRetiredObservationCallback() throws {
    // Hypothesis: a stable reader can stay registered to both the old and new
    // registrar, allowing the retired model to drive a stale recomputation.
    let first = ObservationEffects004Value(name: "first")
    let second = ObservationEffects004Value(name: "second")
    let holder = ObservationEffects004Holder(current: first)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects004"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects004View(holder: holder)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      first.value = generation
      var frame = try harness.render()
      #expect(frame.contains("004 first \(generation)"))

      holder.current = second
      frame = try harness.render()
      #expect(frame.contains("004 second \(generation - 1)"))

      first.value = generation + 100
      frame = try harness.render()
      #expect(frame.contains("004 second \(generation - 1)"))

      second.value = generation
      frame = try harness.render()
      #expect(frame.contains("004 second \(generation)"))

      holder.current = first
      _ = try harness.render()
    }
  }
}

private struct ObservationEffects004View: View {
  let holder: ObservationEffects004Holder

  var body: some View {
    Text("004 \(holder.current.name) \(holder.current.value)")
      .id("observation-effects-004-reader")
  }
}

@Observable
private final class ObservationEffects004Holder {
  var current: ObservationEffects004Value

  init(current: ObservationEffects004Value) {
    self.current = current
  }
}

@Observable
private final class ObservationEffects004Value {
  let name: String
  var value = 0

  init(name: String) {
    self.name = name
  }
}

// MARK: - Attempt 005: selected observable collection element replacement

extension FrameworkStressObservationEffectsTests {
  @Test(
    "stress observation effects 005 replacing the selected collection element rebinds observation")
  func observationEffects005SelectedCollectionReplacementRebindsObservation() throws {
    // Hypothesis: an indexed collection read may keep the registrar belonging
    // to the element previously stored at that index.
    let retired = ObservationEffects005Item(id: 0, value: 0)
    let live = ObservationEffects005Item(id: 0, value: 100)
    let store = ObservationEffects005Store(items: [retired])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects005"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects005View(store: store)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      retired.value = generation
      var frame = try harness.render()
      #expect(frame.contains("005 selected \(generation)"))

      live.value = 100 + generation
      store.items[0] = live
      frame = try harness.render()
      #expect(frame.contains("005 selected \(100 + generation)"))

      retired.value = 1000 + generation
      frame = try harness.render()
      #expect(frame.contains("005 selected \(100 + generation)"))

      store.items[0] = retired
      retired.value = generation
      _ = try harness.render()
    }
  }
}

private struct ObservationEffects005View: View {
  let store: ObservationEffects005Store

  var body: some View {
    Text("005 selected \(store.items[0].value)")
  }
}

@Observable
private final class ObservationEffects005Store {
  var items: [ObservationEffects005Item]

  init(items: [ObservationEffects005Item]) {
    self.items = items
  }
}

@Observable
private final class ObservationEffects005Item: Identifiable {
  let id: Int
  var value: Int

  init(id: Int, value: Int) {
    self.id = id
    self.value = value
  }
}

// MARK: - Attempt 006: observable child-object replacement

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 006 replacing a nested child arms the new registrar")
  func observationEffects006ReplacingNestedChildArmsNewRegistrar() throws {
    // Hypothesis: tracking the parent child property may suppress the nested
    // registrar replacement when the child identity changes repeatedly.
    let first = ObservationEffects006Child(label: "A")
    let second = ObservationEffects006Child(label: "B")
    let parent = ObservationEffects006Parent(child: first)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects006"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects006View(parent: parent)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      parent.child = generation.isMultiple(of: 2) ? first : second
      parent.child.value = generation
      let frame = try harness.render()
      #expect(frame.contains("006 \(parent.child.label) \(generation)"))
    }
  }
}

private struct ObservationEffects006View: View {
  let parent: ObservationEffects006Parent

  var body: some View {
    Text("006 \(parent.child.label) \(parent.child.value)")
  }
}

@Observable
private final class ObservationEffects006Parent {
  var child: ObservationEffects006Child

  init(child: ObservationEffects006Child) {
    self.child = child
  }
}

@Observable
private final class ObservationEffects006Child {
  let label: String
  var value = 0

  init(label: String) {
    self.label = label
  }
}

// MARK: - Attempt 007: AnyView observable payload switching

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 007 AnyView type churn follows the live observable payload")
  func observationEffects007AnyViewTypeChurnFollowsLiveObservablePayload() throws {
    // Hypothesis: AnyView memoization may preserve the observation pass from
    // the erased payload type that previously occupied the stable slot.
    let model = ObservationEffects007Model()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects007"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects007Root(model: model)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      model.showsPrimary.toggle()
      if model.showsPrimary {
        model.primary = generation
      } else {
        model.secondary = generation
      }
      let frame = try harness.render()
      #expect(frame.contains("007 live \(generation)"))
    }
  }
}

private struct ObservationEffects007Root: View {
  let model: ObservationEffects007Model

  var body: some View {
    if model.showsPrimary {
      AnyView(ObservationEffects007Primary(model: model))
    } else {
      AnyView(ObservationEffects007Secondary(model: model))
    }
  }
}

@Observable
private final class ObservationEffects007Model {
  var showsPrimary = true
  var primary = 0
  var secondary = 0
}

private struct ObservationEffects007Primary: View {
  let model: ObservationEffects007Model

  var body: some View {
    Text("007 live \(model.primary)")
  }
}

private struct ObservationEffects007Secondary: View {
  let model: ObservationEffects007Model

  var body: some View {
    Text("007 live \(model.secondary)")
  }
}

// MARK: - Attempt 008: conditional observation teardown pruning

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 008 removed readers leave no observation-pass orphan")
  func observationEffects008RemovedReadersLeaveNoObservationPassOrphan() throws {
    // Hypothesis: ViewNodeID pruning may miss an observed conditional child
    // after repeated remove/reinsert cycles and grow stale pass records.
    let model = ObservationEffects008Model()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects008"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects008View(model: model)
    }
    defer { harness.shutdown() }

    for generation in 1...20 {
      model.isVisible = false
      var frame = try harness.render()
      #expect(frame.contains("008 hidden"))
      #expect(harness.runLoop.observationBridge.makeCheckpoint().observedPasses.count <= 1)

      model.value = generation
      frame = try harness.render()
      #expect(frame.contains("008 hidden"))

      model.isVisible = true
      frame = try harness.render()
      #expect(frame.contains("008 visible \(generation)"))
      #expect(harness.runLoop.observationBridge.makeCheckpoint().observedPasses.count <= 2)
    }
  }
}

private struct ObservationEffects008View: View {
  let model: ObservationEffects008Model

  var body: some View {
    if model.isVisible {
      Text("008 visible \(model.value)")
        .id("observation-effects-008-reader")
    } else {
      Text("008 hidden")
    }
  }
}

@Observable
private final class ObservationEffects008Model {
  var isVisible = true
  var value = 0
}

// MARK: - Attempt 009: targeted environment-writer insertion and removal

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 009 a conditional writer stays isolated to its reader")
  func observationEffects009ConditionalWriterStaysIsolatedToReader() throws {
    // Hypothesis: inserting a writer around one stable reader can contaminate
    // a sibling snapshot or leave the override behind after removal.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects009"),
      size: .init(width: 62, height: 8)
    ) {
      ObservationEffects009View()
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      var frame = try harness.clickText("Toggle Writer 009")
      #expect(frame.contains("009 targeted override-\(generation - 1)"))
      #expect(frame.contains("009 sibling base-\(generation - 1)"))

      frame = try harness.clickText("Advance Environment 009")
      #expect(frame.contains("009 targeted override-\(generation)"))
      #expect(frame.contains("009 sibling base-\(generation)"))

      frame = try harness.clickText("Toggle Writer 009")
      #expect(frame.contains("009 targeted base-\(generation)"))
      #expect(frame.contains("009 sibling base-\(generation)"))
    }
  }
}

private enum ObservationEffectsStringEnvironmentKey: EnvironmentKey {
  static let defaultValue = "default"
}

private enum ObservationEffectsIntEnvironmentKey: EnvironmentKey {
  static let defaultValue = -1
}

private enum ObservationEffectsAuxEnvironmentKey: EnvironmentKey {
  static let defaultValue = "aux-default"
}

extension EnvironmentValues {
  fileprivate var observationEffectsString: String {
    get { self[ObservationEffectsStringEnvironmentKey.self] }
    set { self[ObservationEffectsStringEnvironmentKey.self] = newValue }
  }

  fileprivate var observationEffectsInt: Int {
    get { self[ObservationEffectsIntEnvironmentKey.self] }
    set { self[ObservationEffectsIntEnvironmentKey.self] = newValue }
  }

  fileprivate var observationEffectsAux: String {
    get { self[ObservationEffectsAuxEnvironmentKey.self] }
    set { self[ObservationEffectsAuxEnvironmentKey.self] = newValue }
  }
}

private struct ObservationEffects009Reader: View {
  let label: String
  @Environment(\.observationEffectsString) private var value

  var body: some View {
    Text("009 \(label) \(value)")
  }
}

private struct ObservationEffects009View: View {
  @State private var generation = 0
  @State private var usesWriter = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Writer 009") { usesWriter.toggle() }
      Button("Advance Environment 009") { generation += 1 }
      if usesWriter {
        ObservationEffects009Reader(label: "targeted")
          .environment(\.observationEffectsString, "override-\(generation)")
          .id("observation-effects-009-target")
      } else {
        ObservationEffects009Reader(label: "targeted")
          .id("observation-effects-009-target")
      }
      ObservationEffects009Reader(label: "sibling")
    }
    .environment(\.observationEffectsString, "base-\(generation)")
  }
}

// MARK: - Attempt 010: stacked environment-writer order churn

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 010 stacked writers preserve closest-modifier precedence")
  func observationEffects010StackedWritersPreserveClosestPrecedence() throws {
    // Hypothesis: retained environment snapshots can ignore modifier-order
    // changes when the same key is written twice on one stable reader.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects010"),
      size: .init(width: 58, height: 6)
    ) {
      ObservationEffects010View()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Flip Writer Order 010")
      let expected = generation.isMultiple(of: 2) ? "first" : "second"
      #expect(frame.contains("010 value \(expected)-\(generation)"))
    }
  }
}

private struct ObservationEffects010Reader: View {
  @Environment(\.observationEffectsString) private var value

  var body: some View {
    Text("010 value \(value)")
  }
}

private struct ObservationEffects010View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Flip Writer Order 010") { generation += 1 }
      target
    }
  }

  @ViewBuilder private var target: some View {
    if generation.isMultiple(of: 2) {
      ObservationEffects010Reader()
        .environment(\.observationEffectsString, "first-\(generation)")
        .environment(\.observationEffectsString, "second-\(generation)")
        .id("observation-effects-010-reader")
    } else {
      ObservationEffects010Reader()
        .environment(\.observationEffectsString, "second-\(generation)")
        .environment(\.observationEffectsString, "first-\(generation)")
        .id("observation-effects-010-reader")
    }
  }
}

// MARK: - Attempt 011: transformEnvironment closure freshness

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 011 transformEnvironment applies its current captured payload")
  func observationEffects011TransformEnvironmentAppliesCurrentPayload() throws {
    // Hypothesis: retained modifier resolution can reuse the first transform
    // closure even as the captured generation changes on a stable owner.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects011"),
      size: .init(width: 62, height: 6)
    ) {
      ObservationEffects011View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Advance Transform 011")
      #expect(frame.contains("011 value base|transform-\(generation)"))
    }
  }
}

private struct ObservationEffects011Reader: View {
  @Environment(\.observationEffectsString) private var value

  var body: some View {
    Text("011 value \(value)")
  }
}

private struct ObservationEffects011View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Transform 011") { generation += 1 }
      ObservationEffects011Reader()
        .transformEnvironment(\.observationEffectsString) { value in
          value += "|transform-\(generation)"
        }
    }
    .environment(\.observationEffectsString, "base")
  }
}

// MARK: - Attempt 012: environment transform/writer order

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 012 writer and transform order remains semantic after churn")
  func observationEffects012WriterTransformOrderRemainsSemantic() throws {
    // Hypothesis: a stable environment chain may retain its prior fold order
    // when a writer and a transform exchange structural positions.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects012"),
      size: .init(width: 62, height: 6)
    ) {
      ObservationEffects012View()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Flip Transform Order 012")
      let suffix = generation.isMultiple(of: 2) ? "" : "|T\(generation)"
      if generation.isMultiple(of: 2) {
        #expect(frame.contains("012 value writer-\(generation)\(suffix)"))
      } else {
        withKnownIssue("A reordered transformEnvironment keeps its generation-zero closure") {
          #expect(frame.contains("012 value writer-\(generation)\(suffix)"))
        }
      }
    }
  }
}

private struct ObservationEffects012Reader: View {
  @Environment(\.observationEffectsString) private var value

  var body: some View {
    Text("012 value \(value)")
  }
}

private struct ObservationEffects012View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Flip Transform Order 012") { generation += 1 }
      target
    }
  }

  @ViewBuilder private var target: some View {
    if generation.isMultiple(of: 2) {
      ObservationEffects012Reader()
        .environment(\.observationEffectsString, "writer-\(generation)")
        .transformEnvironment(\.observationEffectsString) { $0 += "|T\(generation)" }
        .id("observation-effects-012-reader")
    } else {
      ObservationEffects012Reader()
        .transformEnvironment(\.observationEffectsString) { $0 += "|T\(generation)" }
        .environment(\.observationEffectsString, "writer-\(generation)")
        .id("observation-effects-012-reader")
    }
  }
}

// MARK: - Attempt 013: unrelated environment-key churn

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 013 unrelated key churn never masks a later dependency change")
  func observationEffects013UnrelatedKeyChurnDoesNotMaskDependencyChange() throws {
    // Hypothesis: selective environment dependency bookkeeping may advance a
    // reader's reuse snapshot on an unrelated key and miss its next real key.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects013"),
      size: .init(width: 62, height: 7)
    ) {
      ObservationEffects013View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      var frame = try harness.clickText("Advance Unrelated 013")
      #expect(frame.contains("013 value \(generation - 1)"))
      frame = try harness.clickText("Advance Dependency 013")
      #expect(frame.contains("013 value \(generation)"))
    }
  }
}

private struct ObservationEffects013Reader: View {
  @Environment(\.observationEffectsInt) private var value

  var body: some View {
    Text("013 value \(value)")
  }
}

private struct ObservationEffects013View: View {
  @State private var value = 0
  @State private var unrelated = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Unrelated 013") { unrelated += 1 }
      Button("Advance Dependency 013") { value += 1 }
      ObservationEffects013Reader()
    }
    .environment(\.observationEffectsInt, value)
    .environment(\.observationEffectsAux, "aux-\(unrelated)")
  }
}

// MARK: - Attempt 014: duplicate identities with distinct environment overrides

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 014 duplicate identities retain distinct environment snapshots")
  func observationEffects014DuplicateIdentitiesRetainDistinctEnvironmentSnapshots() throws {
    // Hypothesis: dependency indexing by runtime identity can collapse direct
    // duplicate siblings and publish one sibling's override to both readers.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects014"),
      size: .init(width: 62, height: 7)
    ) {
      ObservationEffects014View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Advance Duplicates 014")
      #expect(frame.contains("014 first A-\(generation)"))
      #expect(frame.contains("014 second B-\(generation)"))
    }
  }
}

private struct ObservationEffects014Reader: View {
  let label: String
  @Environment(\.observationEffectsString) private var value

  var body: some View {
    Text("014 \(label) \(value)")
  }
}

private struct ObservationEffects014View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Duplicates 014") { generation += 1 }
      ObservationEffects014Reader(label: "first")
        .environment(\.observationEffectsString, "A-\(generation)")
        .id("observation-effects-014-duplicate")
      ObservationEffects014Reader(label: "second")
        .environment(\.observationEffectsString, "B-\(generation)")
        .id("observation-effects-014-duplicate")
    }
  }
}

// MARK: - Attempt 015: non-Equatable CustomReflectable environment equality

extension FrameworkStressObservationEffectsTests {
  @Test(
    "stress observation effects 015 custom reflection collisions do not hide environment changes")
  func observationEffects015CustomReflectionCollisionDoesNotHideEnvironmentChange() throws {
    // Hypothesis: non-Equatable environment equality falls back to reflection,
    // so two payloads with the same custom mirror may compare as unchanged.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects015"),
      size: .init(width: 62, height: 6)
    ) {
      ObservationEffects015View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Replace Reflected Value 015")
      #expect(frame.contains("015 payload \(generation)"))
    }
  }
}

private struct ObservationEffects015Value: Sendable, CustomReflectable {
  var payload: Int

  var customMirror: Mirror {
    Mirror(self, children: ["constant": 0])
  }
}

private enum ObservationEffects015EnvironmentKey: EnvironmentKey {
  static let defaultValue = ObservationEffects015Value(payload: -1)
}

extension EnvironmentValues {
  fileprivate var observationEffects015Value: ObservationEffects015Value {
    get { self[ObservationEffects015EnvironmentKey.self] }
    set { self[ObservationEffects015EnvironmentKey.self] = newValue }
  }
}

private struct ObservationEffects015Reader: View {
  @Environment(\.observationEffects015Value) private var value

  var body: some View {
    Text("015 payload \(value.payload)")
  }
}

private struct ObservationEffects015View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Reflected Value 015") { generation += 1 }
      ObservationEffects015Reader()
        .environment(
          \.observationEffects015Value,
          ObservationEffects015Value(payload: generation)
        )
    }
  }
}

// MARK: - Attempt 016: transformPreference closure freshness

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 016 transformPreference applies its live captured payload")
  func observationEffects016TransformPreferenceAppliesLivePayload() throws {
    // Hypothesis: a stable transform modifier may retain the initial closure
    // while its child preference writer continues publishing current values.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects016"),
      size: .init(width: 62, height: 7)
    ) {
      ObservationEffects016View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Advance Preference 016")
      withKnownIssue("transformPreference retains its generation-zero closure") {
        #expect(frame.contains("016 values [1, \(generation)]"))
      }
    }
  }
}

private enum ObservationEffectsListPreferenceKey: PreferenceKey {
  static let defaultValue: [Int] = []

  static func reduce(value: inout [Int], nextValue: () -> [Int]) {
    value.append(contentsOf: nextValue())
  }
}

private enum ObservationEffectsIntPreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

private enum ObservationEffectsAuxIntPreferenceKey: PreferenceKey {
  static let defaultValue = 0

  static func reduce(value: inout Int, nextValue: () -> Int) {
    value = nextValue()
  }
}

@MainActor
private final class ObservationEffectsEventProbe {
  var events: [String] = []
}

private struct ObservationEffects016View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Preference 016") { generation += 1 }
      Text("source")
        .preference(key: ObservationEffectsListPreferenceKey.self, value: [1])
        .transformPreference(ObservationEffectsListPreferenceKey.self) { value in
          value.append(generation)
        }
        .frame(width: 58, height: 2, alignment: .topLeading)
        .overlayPreferenceValue(
          ObservationEffectsListPreferenceKey.self,
          alignment: .bottomLeading
        ) { value in
          Text("016 values \(value)")
        }
    }
  }
}

// MARK: - Attempt 017: preference writer/transform topology churn

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 017 preference writer and transform retain authored order")
  func observationEffects017PreferenceWriterTransformRetainOrder() throws {
    // Hypothesis: preference folding can retain the previous modifier topology
    // after a writer and transform exchange places at a stable identity.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects017"),
      size: .init(width: 66, height: 7)
    ) {
      ObservationEffects017View()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      let frame = try harness.clickText("Flip Preference Order 017")
      let expected =
        generation.isMultiple(of: 2)
        ? "[\(generation), \(100 + generation)]"
        : "[\(100 + generation), \(generation)]"
      withKnownIssue("A reordered transformPreference retains its generation-zero closure") {
        #expect(frame.contains("017 values \(expected)"))
      }
    }
  }
}

private struct ObservationEffects017View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Flip Preference Order 017") { generation += 1 }
      target
        .frame(width: 62, height: 2, alignment: .topLeading)
        .overlayPreferenceValue(
          ObservationEffectsListPreferenceKey.self,
          alignment: .bottomLeading
        ) { value in
          Text("017 values \(value)")
        }
    }
  }

  @ViewBuilder private var target: some View {
    if generation.isMultiple(of: 2) {
      Text("source")
        .preference(key: ObservationEffectsListPreferenceKey.self, value: [generation])
        .transformPreference(ObservationEffectsListPreferenceKey.self) {
          $0.append(100 + generation)
        }
        .id("observation-effects-017-source")
    } else {
      Text("source")
        .transformPreference(ObservationEffectsListPreferenceKey.self) {
          $0.append(100 + generation)
        }
        .preference(key: ObservationEffectsListPreferenceKey.self, value: [generation])
        .id("observation-effects-017-source")
    }
  }
}

// MARK: - Attempt 018: overlayPreferenceValue payload freshness

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 018 preference overlay follows erased source replacement")
  func observationEffects018PreferenceOverlayFollowsErasedSourceReplacement() throws {
    // Hypothesis: the overlay transform may keep the reduced payload from the
    // prior erased source node when the source type and value change together.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects018"),
      size: .init(width: 64, height: 8)
    ) {
      ObservationEffects018View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Replace Preference Source 018")
      #expect(frame.contains("018 overlay [\(generation)]"))
    }
  }
}

private struct ObservationEffects018View: View {
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace Preference Source 018") { generation += 1 }
      source
        .frame(width: 60, height: 2, alignment: .topLeading)
        .overlayPreferenceValue(
          ObservationEffectsListPreferenceKey.self,
          alignment: .bottomLeading
        ) { value in
          Text("018 overlay \(value)")
        }
    }
  }

  private var source: AnyView {
    if generation.isMultiple(of: 2) {
      return AnyView(
        Text("even source")
          .preference(key: ObservationEffectsListPreferenceKey.self, value: [generation])
      )
    }
    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        Text("odd source")
      }
      .preference(key: ObservationEffectsListPreferenceKey.self, value: [generation])
    )
  }
}

// MARK: - Attempt 019: preference background after source removal

extension FrameworkStressObservationEffectsTests {
  @Test(
    "stress observation effects 019 removing the last source restores the default background payload"
  )
  func observationEffects019RemovingLastSourceRestoresDefaultBackgroundPayload() throws {
    // Hypothesis: late preference reconciliation can carry the departed
    // source's reduced value into a background reader for another frame.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects019"),
      size: .init(width: 68, height: 8)
    ) {
      ObservationEffects019View()
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      var frame = try harness.clickText("Toggle Preference Source 019")
      #expect(frame.contains("019 background []"))
      frame = try harness.clickText("Advance Hidden Source 019")
      #expect(frame.contains("019 background []"))
      frame = try harness.clickText("Toggle Preference Source 019")
      #expect(frame.contains("019 background [\(generation)]"))
    }
  }
}

private struct ObservationEffects019View: View {
  @State private var generation = 0
  @State private var showsSource = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Preference Source 019") { showsSource.toggle() }
      Button("Advance Hidden Source 019") { generation += 1 }
      Group {
        if showsSource {
          Text("live source")
            .preference(key: ObservationEffectsListPreferenceKey.self, value: [generation])
        } else {
          Text("no source")
        }
      }
      .frame(width: 64, height: 2, alignment: .topLeading)
      .backgroundPreferenceValue(
        ObservationEffectsListPreferenceKey.self,
        alignment: .bottomLeading
      ) { value in
        Text("019 background \(value)")
      }
    }
  }
}

// MARK: - Attempt 020: optional same-key preference observer insertion

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 020 inserting an observer preserves the survivor baseline")
  func observationEffects020InsertedObserverPreservesSurvivorBaseline() throws {
    // Hypothesis: same-key preference registrations use positional ordinals,
    // so inserting a leading observer can transfer the survivor's baseline.
    let probe = ObservationEffectsEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects020"),
      size: .init(width: 68, height: 8)
    ) {
      ObservationEffects020View(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...8 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Advance Preference 020")
      #expect(probe.events == ["survivor:\(generation * 2 - 1)"])

      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle Leading Observer 020")
      withKnownIssue("An inserted same-key observer inherits the survivor's ordinal baseline") {
        #expect(probe.events == ["leading:\(generation * 2 - 1)"])
      }

      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Advance Preference 020")
      #expect(
        probe.events.sorted()
          == ["leading:\(generation * 2)", "survivor:\(generation * 2)"].sorted()
      )

      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle Leading Observer 020")
      #expect(probe.events.isEmpty)
    }
  }
}

private struct ObservationEffects020View: View {
  let probe: ObservationEffectsEventProbe
  @State private var generation = 0
  @State private var hasLeadingObserver = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Preference 020") { generation += 1 }
      Button("Toggle Leading Observer 020") { hasLeadingObserver.toggle() }
      observedSource
    }
  }

  @ViewBuilder private var observedSource: some View {
    if hasLeadingObserver {
      source
        .onPreferenceChange(ObservationEffectsIntPreferenceKey.self) { value in
          probe.events.append("leading:\(value)")
        }
        .onPreferenceChange(ObservationEffectsIntPreferenceKey.self) { value in
          probe.events.append("survivor:\(value)")
        }
    } else {
      source
        .onPreferenceChange(ObservationEffectsIntPreferenceKey.self) { value in
          probe.events.append("survivor:\(value)")
        }
    }
  }

  private var source: some View {
    Text("020 preference \(generation)")
      .preference(key: ObservationEffectsIntPreferenceKey.self, value: generation)
      .id("observation-effects-020-source")
  }
}

// MARK: - Attempt 021: different preference-key observers on one owner

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 021 different preference keys keep independent registrations")
  func observationEffects021DifferentPreferenceKeysKeepIndependentRegistrations() throws {
    // Hypothesis: observer ordinal assignment can alias two key types attached
    // to the same owner when both update during every committed frame.
    let probe = ObservationEffectsEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects021"),
      size: .init(width: 68, height: 7)
    ) {
      ObservationEffects021View(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Advance Two Preferences 021")
      #expect(
        probe.events.sorted()
          == ["primary:\(generation)", "aux:\(100 + generation)"].sorted()
      )
      #expect(harness.preferenceObservationRegistrationCount == 2)
    }
  }
}

private struct ObservationEffects021View: View {
  let probe: ObservationEffectsEventProbe
  @State private var generation = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Advance Two Preferences 021") { generation += 1 }
      Text("021 source \(generation)")
        .preference(key: ObservationEffectsIntPreferenceKey.self, value: generation)
        .preference(key: ObservationEffectsAuxIntPreferenceKey.self, value: 100 + generation)
        .onPreferenceChange(ObservationEffectsIntPreferenceKey.self) { value in
          probe.events.append("primary:\(value)")
        }
        .onPreferenceChange(ObservationEffectsAuxIntPreferenceKey.self) { value in
          probe.events.append("aux:\(value)")
        }
    }
  }
}

// MARK: - Attempt 022: collection preference reduction after reorder

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 022 collection preference reduction follows entity reorder")
  func observationEffects022CollectionPreferenceReductionFollowsEntityReorder() throws {
    // Hypothesis: retained ForEach nodes can be traversed in their prior order
    // while reducing fresh preferences from a reordered entity collection.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects022"),
      size: .init(width: 68, height: 9)
    ) {
      ObservationEffects022View()
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      let frame = try harness.clickText("Reorder Preference Rows 022")
      let expected = generation.isMultiple(of: 2) ? "[1, 2, 3]" : "[3, 2, 1]"
      #expect(frame.contains("022 reduced \(expected)"))
    }
  }
}

private struct ObservationEffects022Item: Identifiable {
  let id: Int
}

private struct ObservationEffects022View: View {
  @State private var generation = 0

  private var items: [ObservationEffects022Item] {
    let ids = generation.isMultiple(of: 2) ? [1, 2, 3] : [3, 2, 1]
    return ids.map(ObservationEffects022Item.init(id:))
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Preference Rows 022") { generation += 1 }
      VStack(alignment: .leading, spacing: 0) {
        ForEach(items) { item in
          Text("row \(item.id)")
            .preference(key: ObservationEffectsListPreferenceKey.self, value: [item.id])
        }
      }
      .frame(width: 64, height: 4, alignment: .topLeading)
      .overlayPreferenceValue(
        ObservationEffectsListPreferenceKey.self,
        alignment: .bottomLeading
      ) { value in
        Text("022 reduced \(value)")
      }
    }
  }
}

// MARK: - Attempt 023: Optional onChange baselines

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 023 Optional onChange preserves nil and some transitions")
  func observationEffects023OptionalOnChangePreservesTransitions() throws {
    // Hypothesis: the graph-level baseline box can confuse Optional.none with
    // an absent baseline and swallow nil-to-some or some-to-nil transitions.
    let probe = ObservationEffectsEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects023"),
      size: .init(width: 68, height: 9)
    ) {
      ObservationEffects023View(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Set Optional 023")
      #expect(probe.events == ["nil->\(generation)"])

      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Bump Optional 023")
      #expect(probe.events == ["\(generation)->\(generation + 1)"])

      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Clear Optional 023")
      #expect(probe.events == ["\(generation + 1)->nil"])
    }
  }
}

private struct ObservationEffects023View: View {
  let probe: ObservationEffectsEventProbe
  @State private var generation = 0
  @State private var value: Int?

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Set Optional 023") {
        generation += 1
        value = generation
      }
      Button("Bump Optional 023") { value = value.map { $0 + 1 } }
      Button("Clear Optional 023") { value = nil }
      Text("023 value \(value.map(String.init) ?? "nil")")
        .onChange(of: value) { oldValue, newValue in
          probe.events.append(
            "\(oldValue.map(String.init) ?? "nil")->\(newValue.map(String.init) ?? "nil")"
          )
        }
    }
  }
}

// MARK: - Attempt 024: collection-row onChange baselines

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 024 row onChange baselines follow entities through reorder")
  func observationEffects024RowOnChangeBaselinesFollowEntities() throws {
    // Hypothesis: row baselines or callbacks may remain attached to a prior
    // index after ForEach moves the same entities to new positions.
    let probe = ObservationEffectsEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects024"),
      size: .init(width: 68, height: 10)
    ) {
      ObservationEffects024View(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...16 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Reorder Change Rows 024")
      #expect(probe.events.isEmpty)

      _ = try harness.clickText("Bump Row Two 024")
      #expect(probe.events == ["2:\(generation - 1)->\(generation)"])
    }
  }
}

private struct ObservationEffects024Item: Equatable, Identifiable {
  let id: Int
  var value: Int
}

private struct ObservationEffects024View: View {
  let probe: ObservationEffectsEventProbe
  @State private var reversed = false
  @State private var items = [
    ObservationEffects024Item(id: 1, value: 0),
    ObservationEffects024Item(id: 2, value: 0),
    ObservationEffects024Item(id: 3, value: 0),
  ]

  private var orderedItems: [ObservationEffects024Item] {
    reversed ? Array(items.reversed()) : items
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reorder Change Rows 024") { reversed.toggle() }
      Button("Bump Row Two 024") {
        let index = items.firstIndex { $0.id == 2 }!
        items[index].value += 1
      }
      ForEach(orderedItems) { item in
        Text("024 row \(item.id) value \(item.value)")
          .onChange(of: item.value) { oldValue, newValue in
            probe.events.append("\(item.id):\(oldValue)->\(newValue)")
          }
      }
    }
  }
}

// MARK: - Attempt 025: initial onChange after teardown and reinsertion

extension FrameworkStressObservationEffectsTests {
  @Test("stress observation effects 025 initial onChange fires for every reinserted lifetime")
  func observationEffects025InitialOnChangeFiresForEachReinsertedLifetime() throws {
    // Hypothesis: the graph-level previous-value store can outlive removal of
    // an explicit identity and suppress `initial` for the next lifetime.
    let probe = ObservationEffectsEventProbe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ObservationEffects025"),
      size: .init(width: 70, height: 8)
    ) {
      ObservationEffects025View(probe: probe)
    }
    defer { harness.shutdown() }

    for generation in 1...12 {
      probe.events.removeAll(keepingCapacity: true)
      _ = try harness.clickText("Toggle Observer 025")
      #expect(probe.events.isEmpty)

      _ = try harness.clickText("Advance Hidden Value 025")
      #expect(probe.events.isEmpty)

      _ = try harness.clickText("Toggle Observer 025")
      #expect(probe.events == ["\(generation)->\(generation)"])
    }
  }
}

private struct ObservationEffects025View: View {
  let probe: ObservationEffectsEventProbe
  @State private var isVisible = true
  @State private var value = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Toggle Observer 025") { isVisible.toggle() }
      Button("Advance Hidden Value 025") { value += 1 }
      if isVisible {
        Text("025 value \(value)")
          .onChange(of: value, initial: true) { oldValue, newValue in
            probe.events.append("\(oldValue)->\(newValue)")
          }
          .id("observation-effects-025-observer")
      }
    }
  }
}
