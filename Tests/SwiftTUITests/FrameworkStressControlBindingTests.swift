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

// MARK: - Attempt 002: duplicate-label button entity reorder

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 002 reordered duplicate buttons dispatch by entity")
  func stressControlBinding002ReorderedDuplicateButtonsDispatchByEntity() throws {
    // Hypothesis: after stable ForEach entities reorder, duplicate visible labels can leave their
    // pointer routes associated with the former occurrence order instead of the current entities.
    let probe = ControlStressProbe<[Int]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress002", "Root"),
      size: .init(width: 48, height: 9)
    ) {
      ControlStress002Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reverse buttons 002")
    _ = try harness.clickText("Duplicate action 002")
    _ = try harness.clickText("Duplicate action 002", chooseLast: true)

    #expect(probe.value == [2, 1])
  }
}

@MainActor
private struct ControlStress002Fixture: View {
  let probe: ControlStressProbe<[Int]>
  @State private var isReversed = false

  private var values: [Int] {
    isReversed ? [2, 1] : [1, 2]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse buttons 002") { isReversed = true }
      ForEach(values, id: \.self) { value in
        Button("Duplicate action 002") {
          probe.value.append(value)
        }
      }
    }
  }
}

// MARK: - Attempt 003: button disabled during pointer press

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 003 disabling a pressed button cancels activation")
  func stressControlBinding003DisablingPressedButtonCancelsActivation() throws {
    // Hypothesis: pointer press capture can retain a Button action after the same control becomes
    // disabled, allowing the later mouse-up to dispatch through a now-inert registration.
    let probe = ControlStressProbe(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress003", "Root"),
      size: .init(width: 46, height: 8)
    ) {
      ControlStress003Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    let target = try #require(harness.point(forText: "Press target 003"))
    _ = try harness.sendMouse(.down(.primary), at: target)
    _ = try harness.pressKey(KeyPress(.character("d"), modifiers: .ctrl))
    _ = try harness.sendMouse(.up(.primary), at: target)

    #expect(probe.value == 0)
  }
}

@MainActor
private struct ControlStress003Fixture: View {
  let probe: ControlStressProbe<Int>
  @State private var isEnabled = true

  var body: some View {
    Panel(id: testIdentity("ControlStress003", "Panel")) {
      VStack(alignment: .leading, spacing: 0) {
        Text(isEnabled ? "Target enabled 003" : "Target disabled 003")
        Button("Press target 003") {
          probe.value += 1
        }
        .disabled(!isEnabled)
      }
    }
    .keyCommand("Disable target 003", key: .character("d"), modifiers: .ctrl) {
      isEnabled = false
    }
  }
}

// MARK: - Attempt 004: button role branch replacement

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 004 role replacement refreshes button action")
  func stressControlBinding004RoleReplacementRefreshesButtonAction() throws {
    // Hypothesis: replacing a same-identity Button across role-specialized conditional branches
    // can restore the old action registration while rendering the new role and payload.
    let probe = ControlStressProbe<[Int]>([])
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress004", "Root"),
      size: .init(width: 52, height: 8)
    ) {
      ControlStress004Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Replace role 004")
    _ = try harness.clickText("Role target 004 generation 1")

    #expect(probe.value == [1])
  }
}

@MainActor
private struct ControlStress004Fixture: View {
  let probe: ControlStressProbe<[Int]>
  @State private var generation = 0
  @State private var isDestructive = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Replace role 004") {
        generation = 1
        isDestructive = true
      }
      if isDestructive {
        Button("Role target 004 generation \(generation)", role: .destructive) {
          probe.value.append(generation)
        }
        .id("role-target-004")
      } else {
        Button("Role target 004 generation \(generation)") {
          probe.value.append(generation)
        }
        .id("role-target-004")
      }
    }
  }
}
