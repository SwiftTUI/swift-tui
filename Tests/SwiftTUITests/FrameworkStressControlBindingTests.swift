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

// MARK: - Attempt 005: toggle binding retarget across disabled teardown

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 005 reenabled toggle writes its retargeted binding")
  func stressControlBinding005ReenabledToggleWritesRetargetedBinding() throws {
    // Hypothesis: a Toggle action removed while disabled can be restored with the pre-disable
    // binding even when the same control identity is retargeted before it is enabled again.
    let first = ControlStressProbe(false)
    let second = ControlStressProbe(false)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress005", "Root"),
      size: .init(width: 52, height: 9)
    ) {
      ControlStress005Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget and disable 005")
    _ = try harness.clickText("Reenable toggle 005")
    _ = try harness.clickText("Retargeted toggle 005")

    #expect(first.value == false)
    #expect(first.writes.isEmpty)
    #expect(second.value == true)
    #expect(second.writes == [true])
  }
}

@MainActor
private struct ControlStress005Fixture: View {
  let first: ControlStressProbe<Bool>
  let second: ControlStressProbe<Bool>
  @State private var usesSecond = false
  @State private var isEnabled = true

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget and disable 005") {
        usesSecond = true
        isEnabled = false
      }
      Button("Reenable toggle 005") { isEnabled = true }
      Toggle(
        "Retargeted toggle 005",
        isOn: usesSecond ? second.binding() : first.binding()
      )
      .id("retargeted-toggle-005")
      .disabled(!isEnabled)
    }
  }
}

// MARK: - Attempt 006: duplicate-label toggle entity reorder

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 006 reordered duplicate toggles write by entity")
  func stressControlBinding006ReorderedDuplicateTogglesWriteByEntity() throws {
    // Hypothesis: Toggle action routes can follow occurrence order across a ForEach reorder and
    // mutate the binding formerly displayed at that row rather than the current entity binding.
    let probe = ControlStress006Probe()
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress006", "Root"),
      size: .init(width: 50, height: 9)
    ) {
      ControlStress006Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Reverse toggles 006")
    _ = try harness.clickText("Duplicate toggle 006")
    _ = try harness.clickText("Duplicate toggle 006", chooseLast: true)

    #expect(probe.values == [1: true, 2: true])
    #expect(probe.writtenIDs == [2, 1])
  }
}

@MainActor
private final class ControlStress006Probe {
  var values = [1: false, 2: false]
  var writtenIDs: [Int] = []

  func binding(for id: Int) -> Binding<Bool> {
    Binding(
      get: { self.values[id, default: false] },
      set: {
        self.values[id] = $0
        self.writtenIDs.append(id)
      }
    )
  }
}

@MainActor
private struct ControlStress006Fixture: View {
  let probe: ControlStress006Probe
  @State private var isReversed = false

  private var values: [Int] {
    isReversed ? [2, 1] : [1, 2]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse toggles 006") { isReversed = true }
      ForEach(values, id: \.self) { value in
        Toggle("Duplicate toggle 006", isOn: probe.binding(for: value))
      }
    }
  }
}

// MARK: - Attempt 007: toggle external write during pointer press

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 007 pressed toggle flips the latest external value")
  func stressControlBinding007PressedToggleFlipsLatestExternalValue() throws {
    // Hypothesis: a Toggle pointer press can snapshot the old Boolean and overwrite a newer
    // external binding value when the release activation arrives after an intervening render.
    let probe = ControlStressProbe(false)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress007", "Root"),
      size: .init(width: 48, height: 8)
    ) {
      ControlStress007Fixture(probe: probe)
    }
    defer { harness.shutdown() }

    let target = try #require(harness.point(forText: "Press toggle 007"))
    _ = try harness.sendMouse(.down(.primary), at: target)
    _ = try harness.pressKey(KeyPress(.character("e"), modifiers: .ctrl))
    _ = try harness.sendMouse(.up(.primary), at: target)

    #expect(probe.value == false)
    #expect(probe.writes == [false])
  }
}

@MainActor
private struct ControlStress007Fixture: View {
  let probe: ControlStressProbe<Bool>
  @State private var externalRevision = 0

  var body: some View {
    Panel(id: testIdentity("ControlStress007", "Panel")) {
      VStack(alignment: .leading, spacing: 0) {
        Text("External revision 007 \(externalRevision)")
        Toggle("Press toggle 007", isOn: probe.binding())
      }
    }
    .keyCommand("Externally enable 007", key: .character("e"), modifiers: .ctrl) {
      probe.value = true
      externalRevision += 1
    }
  }
}

// MARK: - Attempt 008: radio picker option-prefix insertion

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 008 inserted picker prefix keeps option routes aligned")
  func stressControlBinding008InsertedPickerPrefixKeepsOptionRoutesAligned() throws {
    // Hypothesis: inserting an option before a stable radio Picker can preserve index-derived
    // pointer handlers from the prior option list and write the tag formerly at the clicked row.
    let selection = ControlStressProbe("a")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress008", "Root"),
      size: .init(width: 48, height: 11)
    ) {
      ControlStress008Fixture(selection: selection)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Prepend option 008")
    _ = try harness.clickText("Beta option 008")

    #expect(selection.value == "b")
    #expect(selection.writes == ["b"])
  }
}

@MainActor
private struct ControlStress008Fixture: View {
  let selection: ControlStressProbe<String>
  @State private var includesPrefix = false

  private var options: [(String, String)] {
    var result = [("a", "Alpha option 008"), ("b", "Beta option 008")]
    if includesPrefix {
      result.insert(("x", "Prefix option 008"), at: 0)
    }
    return result
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Prepend option 008") { includesPrefix = true }
      Picker("Radio picker 008", selection: selection.binding()) {
        ForEach(options, id: \.0) { option in
          Text(option.1).tag(option.0)
        }
      }
      .id("radio-picker-008")
      .pickerStyle(.radioGroup)
    }
  }
}

// MARK: - Attempt 009: picker wheel binding retarget

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 009 picker wheel writes only its current binding")
  func stressControlBinding009PickerWheelWritesOnlyCurrentBinding() throws {
    // Hypothesis: the Picker root pointer route can retain a superseded selection binding even
    // when keyboard navigation for the same stable control has been refreshed correctly.
    let first = ControlStressProbe("c")
    let second = ControlStressProbe("a")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress009", "Root"),
      size: .init(width: 52, height: 9)
    ) {
      ControlStress009Fixture(first: first, second: second)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Retarget picker wheel 009")
    let pickerPoint = try #require(harness.point(forText: "Wheel picker 009"))
    _ = try harness.scrollPointer(at: pickerPoint, deltaY: 1)

    #expect(first.value == "c")
    #expect(first.writes.isEmpty)
    #expect(second.value == "b")
    #expect(second.writes == ["b"])
  }
}

@MainActor
private struct ControlStress009Fixture: View {
  let first: ControlStressProbe<String>
  let second: ControlStressProbe<String>
  @State private var usesSecond = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Retarget picker wheel 009") { usesSecond = true }
      Picker(
        "Wheel picker 009",
        selection: usesSecond ? second.binding() : first.binding()
      ) {
        Text("Alpha 009").tag("a")
        Text("Beta 009").tag("b")
        Text("Gamma 009").tag("c")
      }
      .id("wheel-picker-009")
      .pickerStyle(.segmented)
    }
  }
}

// MARK: - Attempt 010: picker option-order replacement while disabled

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 010 reenabled picker navigates its reordered tags")
  func stressControlBinding010ReenabledPickerNavigatesReorderedTags() throws {
    // Hypothesis: Picker key handlers removed during a disabled interval can be restored with the
    // pre-disable ordered-tag snapshot after options reorder behind the inert control.
    let selection = ControlStressProbe("b")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress010", "Root"),
      size: .init(width: 52, height: 10)
    ) {
      ControlStress010Fixture(selection: selection)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Disable and reverse 010")
    _ = try harness.clickText("Reenable picker 010")
    _ = try harness.focusText("Order picker 010")
    _ = try harness.pressKey(KeyPress(.arrowRight))

    #expect(selection.value == "a")
    #expect(selection.writes == ["a"])
  }
}

@MainActor
private struct ControlStress010Fixture: View {
  let selection: ControlStressProbe<String>
  @State private var isEnabled = true
  @State private var isReversed = false

  private var options: [String] {
    isReversed ? ["c", "b", "a"] : ["a", "b", "c"]
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Disable and reverse 010") {
        isEnabled = false
        isReversed = true
      }
      Button("Reenable picker 010") { isEnabled = true }
      Picker("Order picker 010", selection: selection.binding()) {
        ForEach(options, id: \.self) { option in
          Text("Option 010 \(option)").tag(option)
        }
      }
      .id("order-picker-010")
      .pickerStyle(.segmented)
      .disabled(!isEnabled)
    }
  }
}

// MARK: - Attempt 011: duplicate picker tags avoid redundant writes

extension FrameworkStressControlBindingTests {
  @Test("stress control binding 011 duplicate selected tag avoids binding write")
  func stressControlBinding011DuplicateSelectedTagAvoidsBindingWrite() throws {
    // Hypothesis: option occurrence routing may bypass Picker's selection equality check when two
    // distinct rows carry the same tag, producing a redundant external binding write.
    let selection = ControlStressProbe("shared")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlStress011", "Root"),
      size: .init(width: 44, height: 8)
    ) {
      Picker("Alias picker 011", selection: selection.binding()) {
        Text("First alias 011").tag("shared")
        Text("Second alias 011").tag("shared")
      }
      .pickerStyle(.radioGroup)
    }
    defer { harness.shutdown() }

    _ = try harness.clickText("Second alias 011")

    #expect(selection.value == "shared")
    #expect(selection.writes.isEmpty)
  }
}
