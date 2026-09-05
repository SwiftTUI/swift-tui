import SwiftTUIRuntime
@_spi(StyleFixtures) import SwiftTUIViews
import Testing

// This complete file also typechecks externally with only the fixture SPI.
@MainActor
struct BoundStyleFixtureTests {
  @Test("toggle fixtures expose bound and mixed values", arguments: [false, true])
  func toggle(_ mixed: Bool) {
    var value = false
    var writes = 0
    let config = ToggleStyleConfiguration(
      label: .init { Text("Switch") },
      isOn: Binding(
        get: { value },
        set: {
          value = $0
          writes += 1
        }), isMixed: mixed,
      isEnabled: true, isFocused: true, showsFocusEffect: false, isPressed: false,
      styleEnvironment: .init())
    #expect(!config.focusActive)
    #expect(!text(AutomaticToggleStyle().makeBody(configuration: config)).contains("▌"))
    #expect(
      text(AutomaticToggleStyle().makeBody(configuration: config)).contains(mixed ? "◐" : "○"))
    #expect(text(CheckboxToggleStyle().makeBody(configuration: config)).contains(mixed ? "⊟" : "☐"))
    #expect(text(ButtonToggleStyle().makeBody(configuration: config)).contains("Switch"))
    #expect(writes == 0)
    config.isOn = true
    #expect(value && writes == 1)
    #expect(text(CheckboxToggleStyle().makeBody(configuration: config)).contains(mixed ? "⊟" : "☑"))
  }

  @Test("disclosure fixture bindings write through without rebinding")
  func disclosure() {
    var expanded = false
    let config = DisclosureGroupStyleConfiguration(
      label: .init { Text("Details") }, content: .init { Text("Child") },
      isExpanded: Binding(get: { expanded }, set: { expanded = $0 }),
      isEnabled: true, isFocused: false, showsFocusEffect: true, isPressed: false,
      styleEnvironment: .init())
    #expect(
      !text(AutomaticDisclosureGroupStyle().makeBody(configuration: config)).contains("Child"))
    config.isExpanded = true
    #expect(expanded)
    #expect(text(AutomaticDisclosureGroupStyle().makeBody(configuration: config)).contains("Child"))
    #expect(text(CompactDisclosureGroupStyle().makeBody(configuration: config)).contains("Child"))
    var hiddenFocus = config
    hiddenFocus.isFocused = true
    hiddenFocus.showsFocusEffect = false
    #expect(!text(AutomaticDisclosureGroupStyle().makeBody(configuration: hiddenFocus)).contains("▌"))
  }

  @Test("editor fixtures render inert protected content")
  func editor() {
    let config = TextEditorStyleConfiguration(
      editorContent: .init(displayText: "First\nSecond"),
      isEnabled: true, isFocused: true, showsFocusEffect: true, styleEnvironment: .init())
    let plain = render(PlainTextEditorStyle().makeBody(configuration: config))
    let automatic = render(AutomaticTextEditorStyle().makeBody(configuration: config))
    let rounded = render(RoundedBorderTextEditorStyle().makeBody(configuration: config))
    #expect(plain.rasterSurface.lines.joined().contains("First"))
    #expect(plain.semanticSnapshot.focusRegions.isEmpty)
    #expect(automatic.semanticSnapshot.focusRegions.isEmpty)
    #expect(automatic.rasterSurface == rounded.rasterSurface)
    #expect(plain.rasterSurface != rounded.rasterSurface)
  }

  @Test("progress fixtures expose finite, invalid, indeterminate, and reduced-motion states")
  func progress() {
    var config = ProgressViewStyleConfiguration(
      fractionCompleted: 0.5, label: .init { Text("Working") },
      currentValueLabel: .init { Text("Half") }, barWidth: 8,
      accessibilityReduceMotion: false, styleEnvironment: .init())
    #expect(text(LinearProgressViewStyle().makeBody(configuration: config)).contains("████────"))
    #expect(text(CircularProgressViewStyle().makeBody(configuration: config)).contains("◑"))
    #expect(
      text(AutomaticProgressViewStyle().makeBody(configuration: config))
        == text(LinearProgressViewStyle().makeBody(configuration: config)))
    config.fractionCompleted = .nan
    #expect(text(LinearProgressViewStyle().makeBody(configuration: config)).contains("────────"))
    config.fractionCompleted = nil
    config.indeterminatePhase = 2
    #expect(config.isIndeterminate)
    #expect(text(LinearProgressViewStyle().makeBody(configuration: config)).contains("──███───"))
    config.accessibilityReduceMotion = true
    let reduced = text(CircularProgressViewStyle().makeBody(configuration: config))
    #expect(reduced.contains("Working") && reduced.contains("Half"))
    #expect(!reduced.contains("█"))
  }

  private func text<V: View>(_ view: V) -> String {
    render(view).rasterSurface.lines.joined(separator: "\n")
  }

  private func render<V: View>(_ view: V) -> RenderSnapshot {
    DefaultRenderer().render(
      view, context: .init(identity: Identity(components: ["Fixture"])),
      proposal: .init(width: 24, height: 8))
  }
}
