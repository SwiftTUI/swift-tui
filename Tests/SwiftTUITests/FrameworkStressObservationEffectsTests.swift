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
