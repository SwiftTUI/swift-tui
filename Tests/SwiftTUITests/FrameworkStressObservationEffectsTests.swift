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
