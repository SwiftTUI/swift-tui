import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI control and binding stress behavior", .serialized)
struct FrameworkStressControlBindingTests {}

@MainActor
private final class ControlStressProbe<Value> {
  var value: Value
  var writes: [Value] = []

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes.append($0)
      }
    )
  }
}

// MARK: - Attempt 001: button action reinstall after enablement churn

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 001 reenabled button installs its current action")
  func stressControlBinding001ReenabledButtonInstallsCurrentAction() throws {
    // Hypothesis: removing a disabled Button registration and later restoring the same identity
    // can resurrect the action closure captured before the disabled interval.
    let probe = ControlStressProbe<[Int]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress001", "Root"),
      size: .init(width: 54, height: 10)
    ) {
      ControlStress001Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Disable target 001")
    _ = try harness.clickText("Advance action 001")
    _ = try harness.clickText("Enable target 001")
    _ = try harness.clickText("Fresh button 001 generation 1")

    #expect(probe.value == [1])
  }
}

@MainActor
private struct ControlStress001Fixture: View {
  let probe: ControlStressProbe<[Int]>
  @State private var generation = 0
  @State private var isEnabled = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Disable target 001") { isEnabled = false }
      Button("Advance action 001") { generation += 1 }
      Button("Enable target 001") { isEnabled = true }
      Button("Fresh button 001 generation \(generation)") {
        probe.value.append(generation)
      }
      .id("stable-button-001")
      .disabled(!isEnabled)
    }
  }
}
