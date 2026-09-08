import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

// Compiles externally using the fixture SPI, without testable or package APIs.
@MainActor
struct ValueStyleFixtureTests {
  @Test("slider fixtures render an eight-cell track without installing input routes")
  func sliderFixtures() {
    var configuration = SliderStyleConfiguration(
      label: .init { Text("Level") }, valueLabel: .init { Text("5") },
      fractionCompleted: 0.5, trackCellCount: 8,
      canDecrement: true, canIncrement: true,
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      styleEnvironment: .init())
    let automatic = render(AutomaticSliderStyle().makeBody(configuration: configuration))
    let linear = render(LinearSliderStyle().makeBody(configuration: configuration))
    #expect(automatic.rasterSurface == linear.rasterSurface)
    #expect(linear.rasterSurface.lines.joined().contains("━━━━●───"))
    #expect(linear.semanticSnapshot.interactionRegions.isEmpty)
    configuration.fractionCompleted = 0
    let zero = render(LinearSliderStyle().makeBody(configuration: configuration))
    #expect(zero.rasterSurface.lines.joined().contains("●───────"))
    configuration.fractionCompleted = Double.nan
    #expect(
      render(LinearSliderStyle().makeBody(configuration: configuration)).rasterSurface
        == zero.rasterSurface)
    configuration.trackCellCount = 1
    #expect(
      render(LinearSliderStyle().makeBody(configuration: configuration)).rasterSurface.lines
        .joined().contains("●"))
  }

  @Test("stepper fixtures expose bound state and keep both action routes inert")
  func stepperFixtures() {
    let configuration = StepperStyleConfiguration(
      label: .init { Text("Count") }, valueLabel: .init { Text("0") },
      canDecrement: false, canIncrement: true,
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      styleEnvironment: .init())
    let automatic = render(AutomaticStepperStyle().makeBody(configuration: configuration))
    let compact = render(CompactStepperStyle().makeBody(configuration: configuration))
    #expect(automatic.rasterSurface.lines.joined().contains("◁ 0 ▶"))
    #expect(compact.rasterSurface.lines.joined().contains("− 0 +"))
    #expect(automatic.semanticSnapshot.interactionRegions.isEmpty)
    #expect(compact.semanticSnapshot.interactionRegions.isEmpty)
    let repeated = render(
      VStack {
        configuration.decrement { Text("first") }
        configuration.decrement { Text("second") }
        configuration.increment { Text("third") }
      })
    #expect(repeated.semanticSnapshot.interactionRegions.isEmpty)
    #expect(repeated.diagnostics.runtime.issues.isEmpty)
  }

  @Test("fixture routes hand their content the same disabled state as a live control")
  func fixtureRouteContentState() {
    let stepper = StepperStyleConfiguration(
      label: .init { Text("Count") }, valueLabel: .init { Text("0") },
      canDecrement: false, canIncrement: true,
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      styleEnvironment: .init())
    let text = render(EnabledStateStepperStyle().makeBody(configuration: stepper))
      .rasterSurface.lines.joined()
    #expect(text.contains("less:off"))
    #expect(text.contains("more:on"))
    let slider = SliderStyleConfiguration(
      label: .init { Text("Level") }, valueLabel: .init { Text("5") },
      fractionCompleted: 0.5, trackCellCount: 8,
      isEnabled: false, isFocused: false, showsFocusEffect: true, isPressed: false,
      canDecrement: true, canIncrement: true, styleEnvironment: .init())
    #expect(
      render(EnabledStateSliderStyle().makeBody(configuration: slider)).rasterSurface.lines
        .joined().contains("track:off"))
  }

  @Test("the compact stepper draws no focus rail and keeps its width when focused")
  func compactStepperFocus() {
    var configuration = StepperStyleConfiguration(
      label: .init { Text("Count") }, valueLabel: .init { Text("0") },
      canDecrement: true, canIncrement: true,
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      styleEnvironment: .init())
    let unfocused = render(CompactStepperStyle().makeBody(configuration: configuration))
    configuration.isFocused = true
    let focused = render(CompactStepperStyle().makeBody(configuration: configuration))
    #expect(!focused.rasterSurface.lines.joined().contains("▌"))
    #expect(focused.rasterSurface.lines == unfocused.rasterSurface.lines)
    #expect(focused.rasterSurface.lines.joined().contains("− 0 +"))
    let automatic = render(AutomaticStepperStyle().makeBody(configuration: configuration))
    #expect(automatic.rasterSurface.lines.joined().contains("▌"))
  }

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["Fixture"])),
      proposal: .init(width: 30, height: 8))
  }
}
