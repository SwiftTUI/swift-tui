public import Core

enum ThemeOverrideKey: EnvironmentKey {
  static let defaultValue: Theme? = nil
}

private enum ForegroundStyleKey: EnvironmentKey {
  static let defaultValue: AnyShapeStyle? = nil
}

private enum TintStyleKey: EnvironmentKey {
  static let defaultValue: AnyShapeStyle? = nil
}

private enum TerminalAppearanceKey: EnvironmentKey {
  static let defaultValue = TerminalAppearance.fallback
}

private enum TerminalSizeKey: EnvironmentKey {
  static let defaultValue = Size(width: 80, height: 24)
}

private enum PreferredColorSchemeKey: EnvironmentKey {
  static let defaultValue: ColorScheme? = nil
}

private enum ControlProminenceKey: EnvironmentKey {
  static let defaultValue = ControlProminence.standard
}

private enum ButtonBorderShapeKey: EnvironmentKey {
  static let defaultValue = ButtonBorderShape.automatic
}

private enum ButtonStyleKey: EnvironmentKey {
  static let defaultValue = ButtonStyle.automatic
}

private enum TextFieldStyleKey: EnvironmentKey {
  static let defaultValue = TextFieldStyle.automatic
}

private enum PickerStyleKey: EnvironmentKey {
  static let defaultValue = PickerStyle.automatic
}

private enum ListStyleKey: EnvironmentKey {
  static let defaultValue = ListStyle.automatic
}

private enum TabViewStyleKey: EnvironmentKey {
  static let defaultValue = TabViewStyle.automatic
}

private enum ScrollIndicatorVisibilityKey: EnvironmentKey {
  static let defaultValue = ScrollIndicatorVisibility.automatic
}

private enum TableHeaderVisibilityKey: EnvironmentKey {
  static let defaultValue = TableHeaderVisibility.automatic
}

private enum IsEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

private enum FocusedIdentityKey: EnvironmentKey {
  static let defaultValue: Identity? = nil
}

private enum PressedIdentityKey: EnvironmentKey {
  static let defaultValue: Identity? = nil
}

private enum IsFocusedKey: EnvironmentKey {
  static let defaultValue = false
}

private enum IsFocusEffectEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

private enum PickerViewportLineCountKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

private enum PickerLineWidthKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

extension EnvironmentValues {
  public var terminalAppearance: TerminalAppearance {
    get { self[TerminalAppearanceKey.self] }
    set { self[TerminalAppearanceKey.self] = newValue }
  }

  public var terminalSize: Size {
    get { self[TerminalSizeKey.self] }
    set { self[TerminalSizeKey.self] = newValue }
  }

  public var colorScheme: ColorScheme {
    terminalAppearance.applyingPreferredColorScheme(preferredColorScheme).colorScheme
  }

  public var colorSchemeContrast: ColorSchemeContrast {
    terminalAppearance.applyingPreferredColorScheme(preferredColorScheme).colorSchemeContrast
  }

  public var preferredColorScheme: ColorScheme? {
    get { self[PreferredColorSchemeKey.self] }
    set { self[PreferredColorSchemeKey.self] = newValue }
  }

  public var controlProminence: ControlProminence {
    get { self[ControlProminenceKey.self] }
    set { self[ControlProminenceKey.self] = newValue }
  }

  public var buttonBorderShape: ButtonBorderShape {
    get { self[ButtonBorderShapeKey.self] }
    set { self[ButtonBorderShapeKey.self] = newValue }
  }

  public var buttonStyle: ButtonStyle {
    get { self[ButtonStyleKey.self] }
    set { self[ButtonStyleKey.self] = newValue }
  }

  public var textFieldStyle: TextFieldStyle {
    get { self[TextFieldStyleKey.self] }
    set { self[TextFieldStyleKey.self] = newValue }
  }

  public var pickerStyle: PickerStyle {
    get { self[PickerStyleKey.self] }
    set { self[PickerStyleKey.self] = newValue }
  }

  public var listStyle: ListStyle {
    get { self[ListStyleKey.self] }
    set { self[ListStyleKey.self] = newValue }
  }

  public var tabViewStyle: TabViewStyle {
    get { self[TabViewStyleKey.self] }
    set { self[TabViewStyleKey.self] = newValue }
  }

  public var scrollIndicatorVisibility: ScrollIndicatorVisibility {
    get { self[ScrollIndicatorVisibilityKey.self] }
    set { self[ScrollIndicatorVisibilityKey.self] = newValue }
  }

  public var tableHeaderVisibility: TableHeaderVisibility {
    get { self[TableHeaderVisibilityKey.self] }
    set { self[TableHeaderVisibilityKey.self] = newValue }
  }

  var themeOverride: Theme? {
    get { self[ThemeOverrideKey.self] }
    set { self[ThemeOverrideKey.self] = newValue }
  }

  public var foregroundStyle: AnyShapeStyle? {
    get { self[ForegroundStyleKey.self] }
    set { self[ForegroundStyleKey.self] = newValue }
  }

  public var tintStyle: AnyShapeStyle? {
    get { self[TintStyleKey.self] }
    set { self[TintStyleKey.self] = newValue }
  }

  public var isEnabled: Bool {
    get { self[IsEnabledKey.self] }
    set { self[IsEnabledKey.self] = newValue }
  }

  public var isFocused: Bool {
    get { self[IsFocusedKey.self] }
    set { self[IsFocusedKey.self] = newValue }
  }

  public var isFocusEffectEnabled: Bool {
    get { self[IsFocusEffectEnabledKey.self] }
    set { self[IsFocusEffectEnabledKey.self] = newValue }
  }

  package var focusedIdentity: Identity? {
    get { _focusedIdentity }
    set { _focusedIdentity = newValue }
  }

  package var pressedIdentity: Identity? {
    get { _pressedIdentity }
    set { _pressedIdentity = newValue }
  }

  package var pickerViewportLineCount: Int? {
    get { self[PickerViewportLineCountKey.self] }
    set { self[PickerViewportLineCountKey.self] = newValue }
  }

  package var pickerLineWidth: Int? {
    get { self[PickerLineWidthKey.self] }
    set { self[PickerLineWidthKey.self] = newValue }
  }

  package var styleEnvironmentSnapshot: StyleEnvironmentSnapshot {
    .init(
      appearance: terminalAppearance,
      themeOverride: themeOverride,
      foregroundStyle: foregroundStyle,
      tintStyle: tintStyle,
      preferredColorScheme: preferredColorScheme,
      isEnabled: isEnabled
    )
  }

}
