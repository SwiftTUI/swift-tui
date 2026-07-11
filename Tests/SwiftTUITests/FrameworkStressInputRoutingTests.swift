import Foundation
import Testing

@_spi(Testing) @testable import SwiftTUICore
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("SwiftTUI input-routing stress behavior", .serialized)
struct FrameworkStressInputRoutingTests {}

@MainActor
private final class StressInputBox<Value> {
  var value: Value
  var writeCount = 0

  init(_ value: Value) {
    self.value = value
  }

  func binding() -> Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writeCount += 1
      }
    )
  }
}

// MARK: - Attempt 001: consecutive self-disabling focus targets

extension FrameworkStressInputRoutingTests {
  @Test("Tab continues past two focus targets disabled by the landing transition")
  func stressInputRouting001TabContinuesPastConsecutiveDisabledTargets() throws {
    // Hypothesis: focus convergence may lose its pending traversal after the
    // first landing disables both that region and its immediate successor.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput001Root"),
      size: .init(width: 36, height: 10)
    ) {
      StressInput001Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focusText("Focus A")
    _ = try harness.pressKey(KeyPress(.tab))

    #expect(
      harness.runLoop.focusTracker.currentFocusIdentity
        == (try harness.focusIdentity(forText: "Focus D"))
    )
  }
}

private enum StressInput001Field: Hashable {
  case a
  case b
  case c
  case d
}

private struct StressInput001Fixture: View {
  static let aIdentity = testIdentity("StressInput001", "A")
  static let bIdentity = testIdentity("StressInput001", "B")
  static let cIdentity = testIdentity("StressInput001", "C")
  static let dIdentity = testIdentity("StressInput001", "D")

  @FocusState private var focusedField: StressInput001Field?
  @State private var disablesMiddlePair = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Focus A") {}
        .id(Self.aIdentity)
        .focused($focusedField, equals: .a)
      Button("Focus B") {}
        .id(Self.bIdentity)
        .focused($focusedField, equals: .b)
        .disabled(disablesMiddlePair)
      Button("Focus C") {}
        .id(Self.cIdentity)
        .focused($focusedField, equals: .c)
        .disabled(disablesMiddlePair)
      Button("Focus D") {}
        .id(Self.dIdentity)
        .focused($focusedField, equals: .d)
    }
    .onChange(of: focusedField) { _, next in
      if next == .b {
        disablesMiddlePair = true
      }
    }
  }
}

// MARK: - Attempt 002: reverse traversal through a self-disabling target

extension FrameworkStressInputRoutingTests {
  @Test("Shift-Tab continues backward when its landing target disables itself")
  func stressInputRouting002ReverseTraversalContinuesPastDisabledTarget() throws {
    // Hypothesis: reverse traversal may be re-seated forward when the region
    // reached by Shift-Tab removes itself during focus synchronization.
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("StressInput002Root"),
      size: .init(width: 36, height: 10)
    ) {
      StressInput002Fixture()
    }
    defer { harness.shutdown() }

    _ = try harness.focus(StressInput002Fixture.dIdentity)
    _ = try harness.pressKey(KeyPress(.tab, modifiers: .shift))

    #expect(harness.runLoop.focusTracker.currentFocusIdentity == StressInput002Fixture.aIdentity)
  }
}

private enum StressInput002Field: Hashable {
  case a
  case b
  case c
  case d
}

private struct StressInput002Fixture: View {
  static let aIdentity = testIdentity("StressInput002", "A")
  static let bIdentity = testIdentity("StressInput002", "B")
  static let cIdentity = testIdentity("StressInput002", "C")
  static let dIdentity = testIdentity("StressInput002", "D")

  @FocusState private var focusedField: StressInput002Field?
  @State private var disablesMiddlePair = false

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("Reverse A") {}
        .id(Self.aIdentity)
        .focused($focusedField, equals: .a)
      Button("Reverse B") {}
        .id(Self.bIdentity)
        .focused($focusedField, equals: .b)
        .disabled(disablesMiddlePair)
      Button("Reverse C") {}
        .id(Self.cIdentity)
        .focused($focusedField, equals: .c)
        .disabled(disablesMiddlePair)
      Button("Reverse D") {}
        .id(Self.dIdentity)
        .focused($focusedField, equals: .d)
    }
    .onChange(of: focusedField) { _, next in
      if next == .c {
        disablesMiddlePair = true
      }
    }
  }
}
