import SwiftTUIRuntime
import Testing

@_spi(StyleFixtures) @testable import SwiftTUIViews

// The `.menu` picker built-in drew its focus rail and highlight from the raw
// `isFocused` flag, so `focusEffectDisabled()` still produced the rail. Every
// other picker built-in combined `isFocused` with `showsFocusEffect`; the
// configuration now exposes that conjunction as `focusActive` and the menu
// built-in reads it.
@MainActor
@Suite
struct PickerMenuFocusEffectTests {
  @Test("a focused menu picker under focusEffectDisabled expands without a focus rail")
  func focusedMenuPickerHonorsTheFocusEffect() throws {
    let (effectSurface, _) = Self.render(focusEffectDisabled: false)
    let (plainSurface, plainConfigurationFocusActive) = Self.render(focusEffectDisabled: true)

    // Focus is real in both renders: the menu expands and lists its options.
    #expect(plainSurface.contains("Two"))
    #expect(plainConfigurationFocusActive == false)

    // The trigger row is the one carrying the expansion caret. Its rail is the
    // focus treatment, so it appears only while the focus effect is enabled.
    let effectTrigger = try #require(Self.triggerRow(in: effectSurface))
    let plainTrigger = try #require(Self.triggerRow(in: plainSurface))
    #expect(effectTrigger.contains(Self.rail))
    #expect(!plainTrigger.contains(Self.rail))

    // The rail beside the selected option is a selection marker, not a focus
    // treatment: it survives `focusEffectDisabled()` in both renders, which is
    // why this test reads the trigger row rather than the whole surface.
    #expect(Self.optionRows(in: effectSurface).contains { $0.contains(Self.rail) })
    #expect(Self.optionRows(in: plainSurface).contains { $0.contains(Self.rail) })
  }

  @Test("focusActive is the conjunction of isFocused and showsFocusEffect")
  func focusActiveCombinesFocusAndEffect() {
    var configuration = Self.fixtureConfiguration(isFocused: true, showsFocusEffect: true)
    #expect(configuration.focusActive)
    configuration.showsFocusEffect = false
    #expect(!configuration.focusActive)
    configuration.showsFocusEffect = true
    configuration.isFocused = false
    #expect(!configuration.focusActive)
  }

  // MARK: - Helpers

  /// The glyph both the focus rail and the selection marker draw.
  private static let rail = "▌"

  /// The collapsed or expanded trigger row: the one carrying the caret.
  private static func triggerRow(in surface: String) -> String? {
    surface.split(separator: "\n", omittingEmptySubsequences: false)
      .map(String.init)
      .first { $0.contains("▴") || $0.contains("▾") }
  }

  /// The expanded option rows, which sit below the trigger row.
  private static func optionRows(in surface: String) -> [String] {
    let lines = surface.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    guard let triggerIndex = lines.firstIndex(where: { $0.contains("▴") || $0.contains("▾") })
    else { return [] }
    return Array(lines[lines.index(after: triggerIndex)...])
  }

  /// Renders a focused `.menu` picker and reports the surface text plus the
  /// `focusActive` the style saw, captured through a recording style.
  private static func render(focusEffectDisabled: Bool) -> (String, Bool?) {
    final class SelectionBox {
      var value = 1
    }
    @MainActor final class RecordingBox {
      var focusActive: Bool?
    }
    struct RecordingMenuPickerStyle: PickerStyle {
      let recording: RecordingBox
      var wantsTriggerPointerRoute: Bool { MenuPickerStyle().wantsTriggerPointerRoute }
      func selectionDelta(for event: KeyEvent) -> Int? {
        MenuPickerStyle().selectionDelta(for: event)
      }
      func makeBody(configuration: PickerStyleConfiguration) -> some View {
        recording.focusActive = configuration.focusActive
        return MenuPickerStyle().makeBody(configuration: configuration)
      }
    }

    let box = SelectionBox()
    let recording = RecordingBox()
    let identity = Identity(components: [.named("MenuPicker")])
    var environmentValues = EnvironmentValues()
    environmentValues.focusedIdentity = identity
    let renderer = DefaultRenderer()
    defer { withExtendedLifetime(renderer) {} }
    let artifacts = renderer.render(
      Picker(
        "Mode",
        selection: Binding(
          get: { box.value },
          set: { box.value = $0 }
        )
      ) {
        Text("One").tag(1)
        Text("Two").tag(2)
        Text("Three").tag(3)
      }
      .id(identity)
      .pickerStyle(RecordingMenuPickerStyle(recording: recording))
      .focusEffectDisabled(focusEffectDisabled),
      context: .init(
        identity: Identity(components: [.named("MenuPickerFocusEffect")]),
        environmentValues: environmentValues,
        localKeyHandlerRegistry: LocalKeyHandlerRegistry(),
        applyEnvironmentValues: true
      )
    )
    return (artifacts.rasterSurface.lines.joined(separator: "\n"), recording.focusActive)
  }

  private static func fixtureConfiguration(
    isFocused: Bool,
    showsFocusEffect: Bool
  ) -> PickerStyleConfiguration {
    PickerStyleConfiguration(
      label: .init { Text("Mode") },
      options: [.init(label: "One"), .init(label: "Two")],
      selectedIndex: 0,
      isFocused: isFocused,
      isActiveNavigation: isFocused,
      showsFocusEffect: showsFocusEffect,
      isEnabled: true,
      styleEnvironment: StyleEnvironmentSnapshot(),
      viewportLineCount: nil,
      lineWidth: nil
    )
  }
}
