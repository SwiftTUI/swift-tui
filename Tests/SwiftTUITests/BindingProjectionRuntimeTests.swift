import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Runtime pins for Binding projections (org plan 2026-08-04-002 §4): the
/// stored transaction must ride the real write path — state slot, scheduler
/// segment, animation controller — with zero per-control changes, because
/// every control writes through `Binding.wrappedValue`.
///
/// Precedence is frozen to the SwiftUI probe (2026-08-05): an explicit
/// ambient scope wins over the stored transaction; the stored transaction
/// governs writes made outside any explicit scope (a control interaction is
/// exactly such a write).
@MainActor
@Suite("Binding projection runtime")
struct BindingProjectionRuntimeTests {
  @Test("a projected write animates the dependent subtree")
  func storedAnimationDrivesController() throws {
    let animation = Animation.linear(duration: .milliseconds(300))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BindingProjectionDirect"),
      size: .init(width: 32, height: 5)
    ) {
      ProjectedWriteProbe(animation: animation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      _ = try harness.clickText("StoredWrite")
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(animation.animationBox),
      "the stored animation must reach the controller through the slot write"
    )
  }

  @Test("an ambient withAnimation wins over the stored animation on the real path")
  func ambientWinsOnRealWritePath() throws {
    let stored = Animation.linear(duration: .milliseconds(300))
    let ambient = Animation.easeIn(duration: .milliseconds(700))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BindingProjectionAmbient"),
      size: .init(width: 32, height: 5)
    ) {
      AmbientVersusStoredProbe(stored: stored, ambient: ambient)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      _ = try harness.clickText("AmbientWrite")
    }

    let boxes = controller.debugStateSnapshot().activeAnimationBoxesByKey.values
    #expect(boxes.contains(ambient.animationBox))
    #expect(!boxes.contains(stored.animationBox))
  }

  @Test("an equal-value projected write animates nothing")
  func equalValueWriteAnimatesNothing() throws {
    let animation = Animation.linear(duration: .milliseconds(300))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BindingProjectionEqual"),
      size: .init(width: 32, height: 5)
    ) {
      EqualValueWriteProbe(animation: animation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      _ = try harness.clickText("EqualWrite")
    }

    #expect(
      controller.activeAnimationCount == 0,
      "equal-value writes short-circuit before the ambient read and stay inert"
    )
  }

  @Test("Toggle animates through a projected binding with no per-control change")
  func toggleAnimatesThroughProjectedBinding() throws {
    let animation = Animation.linear(duration: .milliseconds(300))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BindingProjectionToggle"),
      size: .init(width: 40, height: 6)
    ) {
      ToggleProjectionProbe(animation: animation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      _ = try harness.clickText("flip")
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(animation.animationBox),
      "the Toggle write goes through Binding.wrappedValue, so it must animate"
    )
  }

  @Test("Slider animates through a projected binding with no per-control change")
  func sliderAnimatesThroughProjectedBinding() throws {
    let animation = Animation.linear(duration: .milliseconds(300))
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("BindingProjectionSlider"),
      size: .init(width: 48, height: 6)
    ) {
      SliderProjectionProbe(animation: animation)
    }
    defer { harness.shutdown() }
    let controller = harness.runLoop.renderer.internalAnimationController

    try withAnimationSinks(controller) {
      _ = try harness.focusText("level")
      _ = try harness.pressKey(KeyPress(.arrowRight))
    }

    #expect(
      controller.debugStateSnapshot().activeAnimationBoxesByKey.values
        .contains(animation.animationBox),
      "the Slider adjustment writes through Binding.wrappedValue"
    )
  }
}

// MARK: - Probe views

private struct ProjectedWriteProbe: View {
  @State private var level = 0.0
  let animation: Animation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("StoredWrite") {
        $level.animation(animation).wrappedValue = 1
      }
      Text("target").opacity(0.2 + level * 0.6)
    }
  }
}

private struct AmbientVersusStoredProbe: View {
  @State private var level = 0.0
  let stored: Animation
  let ambient: Animation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("AmbientWrite") {
        withAnimation(ambient) {
          $level.animation(stored).wrappedValue = 1
        }
      }
      Text("target").opacity(0.2 + level * 0.6)
    }
  }
}

private struct EqualValueWriteProbe: View {
  @State private var level = 0.5
  let animation: Animation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("EqualWrite") {
        $level.animation(animation).wrappedValue = 0.5
      }
      Text("target").opacity(0.2 + level * 0.6)
    }
  }
}

private struct ToggleProjectionProbe: View {
  @State private var flag = false
  let animation: Animation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Toggle("flip", isOn: $flag.animation(animation))
      Text("target").opacity(flag ? 1.0 : 0.3)
    }
  }
}

private struct SliderProjectionProbe: View {
  @State private var level = 4.0
  let animation: Animation

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Slider("level", value: $level.animation(animation), in: 0...8, step: 1)
      Text("target").opacity(0.1 + level / 10)
    }
  }
}
