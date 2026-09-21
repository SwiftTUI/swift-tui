import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct ControlWheelInvalidationTests {
  @Test(
    "wheel over a control affordance refreshes an external binding's value label",
    arguments: WheelControlKind.allCases, [false, true]
  )
  func wheelRefreshesCapturedValueLabel(
    kind: WheelControlKind, insideScrollView: Bool
  ) throws {
    let model = WheelControlValue()
    let controlIdentity = testIdentity("ControlWheelInvalidation", "Control")
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("ControlWheelInvalidation"),
      size: .init(width: 36, height: 6)
    ) {
      if insideScrollView {
        ScrollView {
          VStack(alignment: .leading, spacing: 0) {
            kind.control(binding: model.binding, identity: controlIdentity)
            ForEach(0..<20) { _ in Text("filler") }
          }
        }
        .scrollIndicators(.hidden)
      } else {
        kind.control(binding: model.binding, identity: controlIdentity)
      }
    }
    defer { harness.shutdown() }

    #expect(harness.frame.contains("9"))
    let initialFocus = harness.runLoop.focusTracker.currentFocusIdentity
    let affordanceIdentity =
      kind.isSlider
      ? sliderTrackIdentity(for: controlIdentity)
      : stepperIncrementIdentity(for: controlIdentity)
    let region = try #require(
      harness.runLoop.latestSemanticSnapshot.interactionRegions.first {
        $0.identity == affordanceIdentity
      }
    )
    let cell = CellPoint(
      x: region.rect.origin.x + region.rect.size.width / 2,
      y: region.rect.origin.y + region.rect.size.height / 2
    )
    let point = Point(x: Double(cell.x), y: Double(cell.y))
    #expect(
      harness.runLoop.hitTarget(at: .cellFallback(cell))?.region.identity
        == affordanceIdentity
    )

    // This manual binding schedules no invalidation itself. The wheel dispatch
    // must invalidate the value-rendering primitive even when the hit region
    // belongs to a press/drag affordance under a separate style-body branch.
    let incremented = try harness.scrollPointer(at: point, deltaY: -1)
    #expect(model.value == 10)
    #expect(incremented.contains("10"), "Rendered frame: \(incremented)")
    #expect(!incremented.contains("9"))
    if kind == .automaticStepper {
      #expect(incremented.contains("▷"))
    }
    #expect(harness.runLoop.focusTracker.currentFocusIdentity == initialFocus)
  }
}

enum WheelControlKind: CaseIterable, Sendable {
  case automaticStepper
  case compactStepper
  case automaticSlider
  case linearSlider

  var isSlider: Bool {
    self == .automaticSlider || self == .linearSlider
  }

  @ViewBuilder @MainActor
  func control(binding: Binding<Int>, identity: Identity) -> some View {
    switch self {
    case .automaticStepper:
      Stepper("Value", value: binding, in: 0...10).stepperStyle(.automatic)
        .id(identity)
    case .compactStepper:
      Stepper("Value", value: binding, in: 0...10).stepperStyle(.compact)
        .id(identity)
    case .automaticSlider:
      Slider("Value", value: binding, in: 0...10).sliderStyle(.automatic)
        .id(identity)
    case .linearSlider:
      Slider("Value", value: binding, in: 0...10).sliderStyle(.linear)
        .id(identity)
    }
  }
}

@MainActor
private final class WheelControlValue {
  var value = 9

  var binding: Binding<Int> {
    Binding(get: { self.value }, set: { self.value = $0 })
  }
}
