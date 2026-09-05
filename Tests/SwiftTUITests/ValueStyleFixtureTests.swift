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
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      canDecrement: true, canIncrement: true, styleEnvironment: .init())
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

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["Fixture"])),
      proposal: .init(width: 30, height: 8))
  }
}
