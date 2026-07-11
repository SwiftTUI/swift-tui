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
