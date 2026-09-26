import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct ValueLabelContrastTests {
  @Test(
    "enabled value-control labels retain text contrast in light and dark appearances",
    arguments: [false, true], [false, true])
  func labels(light: Bool, focused: Bool) throws {
    let appearance: TerminalAppearance =
      light
      ? .init(foregroundColor: .black, backgroundColor: .white, tintColor: .blue)
      : .fallback
    let identity = testIdentity("ValueControl")
    var environment = EnvironmentValues()
    environment.terminalAppearance = appearance
    if focused { environment.focusedIdentity = identity }
    func verify<V: View>(_ control: V, label: Character) throws {
      let surface = DefaultRenderer().render(
        control.id(identity),
        context: .init(identity: testIdentity("Root"), environmentValues: environment),
        proposal: .init(width: 32, height: 3)
      ).rasterSurface
      let cell = try #require(surface.cells.flatMap { $0 }.first { $0.character == label })
      let foreground = cell.style?.foregroundColor ?? appearance.foregroundColor
      let background = cell.style?.backgroundColor ?? appearance.backgroundColor
      #expect(foreground.contrastRatio(to: background) >= 4.5)
    }
    try verify(Slider("Gain", value: .constant(0.5), in: 0...1), label: "G")
    try verify(Stepper("Count", value: .constant(1), in: 0...4), label: "C")
    try verify(
      Stepper("Count", value: .constant(1), in: 0...4).stepperStyle(.compact), label: "C")
  }
}
