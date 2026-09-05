import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

@MainActor
struct ValueControlStyleTests {
  @Test(
    "slider tracks preserve drag capture, typed stepping, and wheel handling",
    arguments: [0, 1, 2, 3])
  func sliderInput(_ index: Int) throws {
    let value = ValueStyleBox(0)
    let styles: [AnySliderStyle] = [
      .automatic, .linear, .init(ConsumerAutomaticSliderStyle()), .init(ConsumerSliderStyle()),
    ]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 48, height: 10)
    ) {
      Slider("Level", value: value.binding, in: 0...10).sliderStyle(styles[index])
    }
    defer { harness.shutdown() }
    let start = try #require(harness.point(forText: index == 3 ? "========" : "●"))
    _ = try harness.drag(from: start, to: .init(x: 44, y: start.y + 2))
    #expect(value.value == 10)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    #expect(value.value == 9)
    let point = try #require(harness.point(forText: "Level"))
    _ = try harness.scrollPointer(at: point, deltaY: 1)
    #expect(value.value == 8)
  }

  @Test("custom slider routes retain Double snapping and formatted values")
  func doubleSlider() throws {
    let value = ValueStyleBox(0.0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 48, height: 10)
    ) {
      Slider("Level", value: value.binding, in: 0.0...1.0, step: 0.25)
        .sliderStyle(ConsumerSliderStyle())
    }
    defer { harness.shutdown() }
    let start = try #require(harness.point(forText: "========"))
    _ = try harness.drag(from: start, to: .init(x: 44, y: start.y + 2))
    #expect(value.value == 1)
    _ = try harness.pressKey(KeyPress(.arrowLeft))
    #expect(value.value == 0.75)
    #expect(harness.frame.contains("0.75"))
  }

  @Test(
    "stepper routes write once and keep bound presses from activating the root",
    arguments: [0, 1, 2, 3])
  func stepperInput(_ index: Int) throws {
    let value = ValueStyleBox(0)
    let styles: [AnyStepperStyle] = [
      .automatic, .compact, .init(ConsumerAutomaticStepperStyle()), .init(ConsumerStepperStyle()),
    ]
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 48, height: 10)
    ) {
      Stepper("Count", value: value.binding, in: 0...2).stepperStyle(styles[index])
    }
    defer { harness.shutdown() }
    _ = try harness.clickText(index == 3 ? "Less" : index == 1 ? "−" : "◁")
    #expect(value.value == 0 && value.writes == 0)
    _ = try harness.clickText(index == 3 ? "More" : index == 1 ? "+" : "▶")
    #expect(value.value == 1 && value.writes == 1)
    _ = try harness.clickText(index == 3 ? "Less" : index == 1 ? "−" : "◀")
    #expect(value.value == 0 && value.writes == 2)
    _ = try harness.pressKey(KeyPress(.arrowRight))
    #expect(value.value == 1 && value.writes == 3)
    _ = try harness.pressKey(KeyPress(.space))
    #expect(value.value == 2 && value.writes == 4)
    _ = try harness.clickText(index == 3 ? "More" : index == 1 ? "+" : "▷")
    #expect(value.value == 2 && value.writes == 4)
  }

  @Test("custom stepper routes retain Double stepping")
  func doubleStepper() throws {
    let value = ValueStyleBox(0.5)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 40, height: 8)
    ) {
      Stepper("Count", value: value.binding, in: 0.0...1.0, step: 0.25)
        .stepperStyle(ConsumerStepperStyle())
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("More")
    #expect(value.value == 0.75 && value.writes == 1)
    #expect(harness.frame.contains("0.75"))
    _ = try harness.clickText("Less")
    #expect(value.value == 0.5 && value.writes == 2)
  }

  @Test("omitting optional routes preserves keyboard value adjustment")
  func omittedRoutes() throws {
    let slider = ValueStyleBox(0)
    let stepper = ValueStyleBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 48, height: 12)
    ) {
      VStack {
        Slider("Level", value: slider.binding, in: 0...10)
          .sliderStyle(ConsumerSliderStyle(omitsRoutes: true))
        Stepper("Count", value: stepper.binding, in: 0...10)
          .stepperStyle(ConsumerStepperStyle(omitsRoutes: true))
      }
    }
    defer { harness.shutdown() }
    _ = try harness.focusText("Level")
    _ = try harness.pressKey(KeyPress(.arrowRight))
    #expect(slider.value == 1)
    _ = try harness.focusText("Count")
    _ = try harness.pressKey(KeyPress(.arrowRight))
    #expect(stepper.value == 1)
    #expect(
      !harness.runLoop.latestSemanticSnapshot.interactionRegions.contains {
        $0.identity.description.contains("SliderTrack")
          || $0.identity.description.contains("StepperDecrement")
          || $0.identity.description.contains("StepperIncrement")
      })
  }

  @Test("disabled custom routes cannot mutate either numeric binding")
  func disabledControls() throws {
    let slider = ValueStyleBox(0)
    let stepper = ValueStyleBox(0)
    let harness = try StressRuntimeHarness(
      rootIdentity: testIdentity("Root"), size: .init(width: 48, height: 12)
    ) {
      VStack {
        Slider("Level", value: slider.binding, in: 0...10).sliderStyle(ConsumerSliderStyle())
        Stepper("Count", value: stepper.binding, in: 0...10).stepperStyle(ConsumerStepperStyle())
      }.disabled(true)
    }
    defer { harness.shutdown() }
    _ = try harness.clickText("========")
    _ = try harness.clickText("More")
    _ = try harness.pressKey(KeyPress(.arrowRight))
    #expect(slider.writes == 0 && stepper.writes == 0)
  }

  @Test("duplicate value-control routes report and keep the first installation")
  func duplicateRoutes() {
    let frame = render(
      VStack {
        Slider("Level", value: .constant(5), in: 0...10)
          .sliderStyle(ConsumerSliderStyle(duplicates: true))
        Stepper("Count", value: .constant(5), in: 0...10)
          .stepperStyle(ConsumerStepperStyle(duplicates: true))
      })
    let issues = frame.diagnostics.runtime.issues.filter { $0.code == "style.duplicateRoute" }
    #expect(issues.count == 3)
    for issue in issues {
      #expect(
        frame.semanticSnapshot.interactionRegions.filter { $0.identity == issue.identity }.count
          == 1)
    }
  }

  @Test(
    "public default value-control styles reproduce the complete raster", arguments: [false, true],
    [false, true])
  func publicDefaultParity(_ enabled: Bool, _ focused: Bool) {
    let identity = testIdentity("Root")
    var environment = EnvironmentValues()
    environment.isEnabled = enabled
    if focused { environment.focusedIdentity = identity }
    let context = ResolveContext(
      identity: identity, environmentValues: environment, applyEnvironmentValues: true)
    let slider = Slider("Level", value: .constant(5), in: 0...10)
    let stepper = Stepper("Count", value: .constant(0), in: 0...10)
    same(slider, slider.sliderStyle(ConsumerAutomaticSliderStyle()), context: context)
    same(slider, slider.sliderStyle(.linear), context: context)
    same(stepper, stepper.stepperStyle(ConsumerAutomaticStepperStyle()), context: context)
  }

  private func same<A: View, B: View>(_ a: A, _ b: B, context: ResolveContext) {
    let actual = DefaultRenderer().render(
      a, context: context, proposal: .init(width: 40, height: 8)
    ).rasterSurface
    let expected = DefaultRenderer().render(
      b, context: context, proposal: .init(width: 40, height: 8)
    ).rasterSurface
    let matches = actual == expected
    #expect(matches, "actual: \(actual.lines) expected: \(expected.lines)")
  }

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: testIdentity("Root")), proposal: .init(width: 48, height: 14))
  }
}

@MainActor
private final class ValueStyleBox<Value: Sendable> {
  var value: Value
  var writes = 0
  init(_ value: Value) { self.value = value }
  var binding: Binding<Value> {
    Binding(
      get: { self.value },
      set: {
        self.value = $0
        self.writes += 1
      })
  }
}
