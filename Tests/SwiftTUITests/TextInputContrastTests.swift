import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
struct TextInputContrastTests {
  @Test(
    "controls retain identifying outlines and glyphs in light and dark appearances",
    arguments: [false, true], [false, true])
  func outlines(light: Bool, focused: Bool) throws {
    let appearance: TerminalAppearance =
      light
      ? .init(foregroundColor: .black, backgroundColor: .white, tintColor: .blue)
      : .fallback
    let identity = testIdentity("Input")
    var environment = EnvironmentValues()
    environment.terminalAppearance = appearance
    if focused { environment.focusedIdentity = identity }
    func verify<V: View>(_ control: V) throws {
      let surface = DefaultRenderer().render(
        control.id(identity),
        context: .init(identity: testIdentity("Root"), environmentValues: environment),
        proposal: .init(width: 32, height: 8)
      ).rasterSurface
      let cells = surface.cells.flatMap { $0 }
      let outlines = cells.filter { cell in
        ["▌", "●", "○", "◉", "◀", "▶"].contains(cell.character)
          || cell.character.unicodeScalars.contains { (0x2500...0x257f).contains($0.value) }
      }
      #expect(!outlines.isEmpty)
      for cell in outlines {
        let foreground = cell.style?.foregroundColor ?? appearance.foregroundColor
        let background = cell.style?.backgroundColor ?? appearance.backgroundColor
        #expect(
          foreground.contrastRatio(to: background) >= 3,
          "\(cell.character) foreground \(foreground.hexString()) background \(background.hexString())"
        )
      }
      if let label = cells.first(where: { $0.character == "N" }) {
        let foreground = label.style?.foregroundColor ?? appearance.foregroundColor
        let background = label.style?.backgroundColor ?? appearance.backgroundColor
        #expect(foreground.contrastRatio(to: background) >= 4.5)
      }
    }
    try verify(TextField("Name", text: .constant("")).textFieldStyle(.roundedBorder))
    try verify(SecureField("Name", text: .constant("")).textFieldStyle(.roundedBorder))
    try verify(TextEditor(text: .constant("")).textEditorStyle(.roundedBorder))
    try verify(Toggle("Enabled", isOn: .constant(false)))
    try verify(Toggle("Enabled", isOn: .constant(true)))
    try verify(Slider("Gain", value: .constant(0.5), in: 0...1))
    try verify(Stepper("Quantity", value: .constant(1), in: 0...5))
  }
}
