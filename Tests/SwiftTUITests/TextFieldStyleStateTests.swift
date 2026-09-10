import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime
@_spi(StyleFixtures) @testable import SwiftTUIViews

/// Renders the state a text-field style can read: `[disabled]` while the
/// field is not enabled, `[keyboard]` while it owns focus, and `[focused]`
/// only while the focus effect applies as well.
private struct StateMarkerTextFieldStyle: TextFieldStyle {
  @MainActor
  func makeBody(configuration: TextFieldStyleConfiguration) -> some View {
    HStack(alignment: .center, spacing: 1) {
      configuration.fieldContent
      if !configuration.isEnabled { Text("[disabled]") }
      if configuration.isFocused { Text("[keyboard]") }
      if configuration.focusActive { Text("[focused]") }
    }
  }
}

/// `TextFieldStyleConfiguration` exposes `isEnabled`, `isFocused`, and
/// `showsFocusEffect` like every sibling configuration, with `focusActive`
/// derived from the last two (org review of the 0.12.1 style system).
@MainActor
struct TextFieldStyleStateTests {
  private let fieldIdentity = testIdentity("StateField")

  private func render<V: View>(_ view: V, focused: Bool) -> String {
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = focused ? fieldIdentity : nil
    return DefaultRenderer().render(
      view.textFieldStyle(StateMarkerTextFieldStyle()),
      context: .init(
        identity: testIdentity("Root"),
        environmentValues: environmentValues,
        applyEnvironmentValues: true
      ),
      proposal: .init(width: 40, height: 1)
    ).rasterSurface.lines.joined(separator: "\n")
  }

  @Test("a disabled text field reports isEnabled false to its style")
  func textFieldStyleReportsDisabled() {
    let surface = render(
      TextField("Name", text: .constant("ada")).id(fieldIdentity).disabled(true),
      focused: false)
    #expect(surface.contains("[disabled]"))
    #expect(!surface.contains("[keyboard]"))
    #expect(!surface.contains("[focused]"))
  }

  @Test("a focused text field reports focusActive to its style")
  func textFieldStyleReportsFocusActive() {
    let surface = render(
      TextField("Name", text: .constant("ada")).id(fieldIdentity),
      focused: true)
    #expect(surface.contains("[keyboard]"))
    #expect(surface.contains("[focused]"))
    #expect(!surface.contains("[disabled]"))
  }

  @Test("focusEffectDisabled keeps isFocused and clears focusActive")
  func textFieldStyleReportsFocusWithoutEffect() {
    let surface = render(
      TextField("Name", text: .constant("ada")).id(fieldIdentity).focusEffectDisabled(),
      focused: true)
    #expect(surface.contains("[keyboard]"))
    #expect(!surface.contains("[focused]"))
  }

  @Test("a text-field fixture derives focusActive from isFocused and showsFocusEffect")
  func textFieldFixtureDerivesFocusActive() {
    func fixture(
      isEnabled: Bool, isFocused: Bool, showsFocusEffect: Bool
    ) -> TextFieldStyleConfiguration {
      TextFieldStyleConfiguration(
        displayText: "ada",
        isShowingPrompt: false,
        label: .init { Text("Name") },
        showsLabel: false,
        chrome: ControlChrome(
          foregroundStyle: AnyShapeStyle(.foreground),
          contentBackgroundStyle: AnyShapeStyle(.background),
          borderForegroundStyle: AnyShapeStyle(.separator)
        ),
        placeholderStyle: AnyShapeStyle(.placeholder),
        isEnabled: isEnabled,
        isFocused: isFocused,
        showsFocusEffect: showsFocusEffect,
        styleEnvironment: StyleEnvironmentSnapshot()
      )
    }
    #expect(fixture(isEnabled: true, isFocused: true, showsFocusEffect: true).focusActive)
    #expect(!fixture(isEnabled: true, isFocused: true, showsFocusEffect: false).focusActive)
    #expect(fixture(isEnabled: true, isFocused: true, showsFocusEffect: false).isFocused)
    #expect(!fixture(isEnabled: true, isFocused: false, showsFocusEffect: true).focusActive)
    #expect(!fixture(isEnabled: false, isFocused: false, showsFocusEffect: true).isEnabled)
  }
}
