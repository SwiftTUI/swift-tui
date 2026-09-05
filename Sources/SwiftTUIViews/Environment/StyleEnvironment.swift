public import SwiftTUICore

private enum LinkStyleKey: EnvironmentKey {
  static let defaultValue = AnyLinkStyle.automatic
}

private enum ScrollViewStyleKey: EnvironmentKey {
  static let defaultValue = AnyScrollViewStyle.automatic
}

private enum SliderStyleKey: EnvironmentKey {
  static let defaultValue = AnySliderStyle.automatic
}

private enum StepperStyleKey: EnvironmentKey {
  static let defaultValue = AnyStepperStyle.automatic
}

enum ThemeKey: EnvironmentKey {
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
  static let defaultValue = CellSize(width: 80, height: 24)
}

private enum SafeAreaInsetsKey: EnvironmentKey {
  static let defaultValue = EdgeInsets.zero
}

private enum ControlProminenceKey: EnvironmentKey {
  static let defaultValue = ControlProminence.standard
}

private enum ButtonBorderShapeKey: EnvironmentKey {
  static let defaultValue = ButtonBorderShape.automatic
}

private enum ButtonStyleKey: EnvironmentKey {
  static let defaultValue = AnyButtonStyle.automatic
}

private enum ToggleStyleKey: EnvironmentKey {
  static let defaultValue = AnyToggleStyle.automatic
}

private enum DisclosureGroupStyleKey: EnvironmentKey {
  static let defaultValue = AnyDisclosureGroupStyle.automatic
}

private enum TextEditorStyleKey: EnvironmentKey {
  static let defaultValue = AnyTextEditorStyle.automatic
}

private enum ProgressViewStyleKey: EnvironmentKey {
  static let defaultValue = AnyProgressViewStyle.automatic
}

private enum LabelStyleKey: EnvironmentKey {
  static let defaultValue = AnyLabelStyle.automatic
}

private enum LabeledContentStyleKey: EnvironmentKey {
  static let defaultValue = AnyLabeledContentStyle.automatic
}

private enum ControlGroupStyleKey: EnvironmentKey {
  static let defaultValue = AnyControlGroupStyle.automatic
}

private enum MenuStyleKey: EnvironmentKey {
  static let defaultValue = AnyMenuStyle.automatic
}

private enum PaletteStyleKey: EnvironmentKey {
  static let defaultValue = AnyPaletteStyle.automatic
}

private enum GroupBoxStyleKey: EnvironmentKey {
  static let defaultValue = AnyGroupBoxStyle.automatic
}

private enum TextFieldStyleKey: EnvironmentKey {
  static let defaultValue = AnyTextFieldStyle.automatic
}

private enum PickerStyleKey: EnvironmentKey {
  static let defaultValue = AnyPickerStyle.automatic
}

private enum ListStyleKey: EnvironmentKey {
  static let defaultValue = AnyListStyle.automatic
}

private enum TableStyleKey: EnvironmentKey {
  static let defaultValue = AnyTableStyle.automatic
}

private enum SpinnerStyleKey: EnvironmentKey {
  static let defaultValue = AnySpinnerStyle.automatic
}

private enum ToolbarStyleKey: EnvironmentKey {
  static let defaultValue = AnyToolbarStyle.defaultTop
}

private enum SheetStyleKey: EnvironmentKey {
  static let defaultValue = AnySheetStyle.automatic
}

private enum PromptStyleKey: EnvironmentKey {
  static let defaultValue = AnyPromptStyle.automatic
}

private enum FullScreenCoverStyleKey: EnvironmentKey {
  static let defaultValue = AnyFullScreenCoverStyle.automatic
}

private enum PopoverStyleKey: EnvironmentKey {
  static let defaultValue = AnyPopoverStyle.automatic
}

private enum TabViewStyleKey: EnvironmentKey {
  static let defaultValue = AnyTabViewStyle.automatic
}

private enum ScrollIndicatorVisibilityKey: EnvironmentKey {
  static let defaultValue = ScrollIndicatorVisibility.automatic
}

private enum HorizontalScrollIndicatorVisibilityKey: EnvironmentKey {
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

private enum IsFocusEffectEnabledKey: EnvironmentKey {
  static let defaultValue = true
}

private enum PickerViewportLineCountKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

private enum PickerLineWidthKey: EnvironmentKey {
  static let defaultValue: Int? = nil
}

/// Attribution-only sentinel: nodes whose evaluation consulted the
/// `focusedIdentity`/`pressedIdentity` side-fields directly (framework
/// controls compare them self-or-descendant style). Distinct from
/// `FocusedIdentityKey`: that set is unioned WHOLESALE into every focus-move
/// suppression scope (arbitrary-comparison wrapper readers), while this key
/// only feeds the root-path predicate that demotes reader-free focus targets
/// to chrome-only members.
private enum RuntimeFocusSideFieldReadKey {}

/// Attribution-only sentinel for TARGET-SCOPED side-field reads
/// (`focusedIdentity(comparedAgainst:)`): the reader declared the exact
/// identities its comparisons target, recorded per-node as
/// `DependencySet.focusComparisonTargets`. The focus-move path predicate
/// treats such a reader as affected only when the moved identity is among
/// its targets, so a distant container reader (a sheet's `ScrollView`,
/// which compares exclusively against itself and its synthetic indicator
/// identities) does not block the chrome-only demotion of an unrelated
/// content descendant.
private enum RuntimeFocusTargetScopedReadKey {}

extension EnvironmentValues {
  package var scrollViewStyle: AnyScrollViewStyle {
    get { self[ScrollViewStyleKey.self] }
    set { self[ScrollViewStyleKey.self] = newValue }
  }

  package var linkStyle: AnyLinkStyle {
    get { self[LinkStyleKey.self] }
    set { self[LinkStyleKey.self] = newValue }
  }

  package var sliderStyle: AnySliderStyle {
    get { self[SliderStyleKey.self] }
    set { self[SliderStyleKey.self] = newValue }
  }

  package var stepperStyle: AnyStepperStyle {
    get { self[StepperStyleKey.self] }
    set { self[StepperStyleKey.self] = newValue }
  }

  package var toggleStyle: AnyToggleStyle {
    get { self[ToggleStyleKey.self] }
    set { self[ToggleStyleKey.self] = newValue }
  }

  package var disclosureGroupStyle: AnyDisclosureGroupStyle {
    get { self[DisclosureGroupStyleKey.self] }
    set { self[DisclosureGroupStyleKey.self] = newValue }
  }

  package var textEditorStyle: AnyTextEditorStyle {
    get { self[TextEditorStyleKey.self] }
    set { self[TextEditorStyleKey.self] = newValue }
  }

  package var progressViewStyle: AnyProgressViewStyle {
    get { self[ProgressViewStyleKey.self] }
    set { self[ProgressViewStyleKey.self] = newValue }
  }

  package static var runtimeFocusStateDependencyKeys: Set<ObjectIdentifier> {
    [
      ObjectIdentifier(FocusedIdentityKey.self),
      ObjectIdentifier(PressedIdentityKey.self),
    ]
  }

  package static var runtimeFocusSideFieldReadDependencyKey: ObjectIdentifier {
    ObjectIdentifier(RuntimeFocusSideFieldReadKey.self)
  }

  package static var runtimeFocusTargetScopedReadDependencyKey: ObjectIdentifier {
    ObjectIdentifier(RuntimeFocusTargetScopedReadKey.self)
  }

  package static func runtimeFocusStateDependencyKey(
    for keyPath: AnyKeyPath
  ) -> ObjectIdentifier? {
    if keyPath == \EnvironmentValues.focusedIdentity {
      return ObjectIdentifier(FocusedIdentityKey.self)
    }
    if keyPath == \EnvironmentValues.pressedIdentity {
      return ObjectIdentifier(PressedIdentityKey.self)
    }
    if keyPath == \EnvironmentValues.isFocused {
      // `isFocused` is derived from `focusedIdentity` (the per-node cone
      // bake), so readers share its runtime focus dependency.
      return ObjectIdentifier(FocusedIdentityKey.self)
    }
    return nil
  }

  public var terminalAppearance: TerminalAppearance {
    get { self[TerminalAppearanceKey.self] }
    set { self[TerminalAppearanceKey.self] = newValue }
  }

  public var terminalSize: CellSize {
    get { self[TerminalSizeKey.self] }
    set { self[TerminalSizeKey.self] = newValue }
  }

  public var safeAreaInsets: EdgeInsets {
    get { self[SafeAreaInsetsKey.self] }
    set { self[SafeAreaInsetsKey.self] = newValue }
  }

  public var colorSchemeContrast: ColorSchemeContrast {
    terminalAppearance.colorSchemeContrast
  }

  public var controlProminence: ControlProminence {
    get { self[ControlProminenceKey.self] }
    set { self[ControlProminenceKey.self] = newValue }
  }

  public var buttonBorderShape: ButtonBorderShape {
    get { self[ButtonBorderShapeKey.self] }
    set { self[ButtonBorderShapeKey.self] = newValue }
  }

  package var buttonStyle: AnyButtonStyle {
    get { self[ButtonStyleKey.self] }
    set { self[ButtonStyleKey.self] = newValue }
  }

  package var labelStyle: AnyLabelStyle {
    get { self[LabelStyleKey.self] }
    set { self[LabelStyleKey.self] = newValue }
  }

  package var labeledContentStyle: AnyLabeledContentStyle {
    get { self[LabeledContentStyleKey.self] }
    set { self[LabeledContentStyleKey.self] = newValue }
  }

  package var controlGroupStyle: AnyControlGroupStyle {
    get { self[ControlGroupStyleKey.self] }
    set { self[ControlGroupStyleKey.self] = newValue }
  }

  package var menuStyle: AnyMenuStyle {
    get { self[MenuStyleKey.self] }
    set { self[MenuStyleKey.self] = newValue }
  }

  package var paletteStyle: AnyPaletteStyle {
    get { self[PaletteStyleKey.self] }
    set { self[PaletteStyleKey.self] = newValue }
  }

  package var groupBoxStyle: AnyGroupBoxStyle {
    get { self[GroupBoxStyleKey.self] }
    set { self[GroupBoxStyleKey.self] = newValue }
  }

  package var textFieldStyle: AnyTextFieldStyle {
    get { self[TextFieldStyleKey.self] }
    set { self[TextFieldStyleKey.self] = newValue }
  }

  package var pickerStyle: AnyPickerStyle {
    get { self[PickerStyleKey.self] }
    set { self[PickerStyleKey.self] = newValue }
  }

  package var listStyle: AnyListStyle {
    get { self[ListStyleKey.self] }
    set { self[ListStyleKey.self] = newValue }
  }

  package var tableStyle: AnyTableStyle {
    get { self[TableStyleKey.self] }
    set { self[TableStyleKey.self] = newValue }
  }

  package var spinnerStyle: AnySpinnerStyle {
    get { self[SpinnerStyleKey.self] }
    set { self[SpinnerStyleKey.self] = newValue }
  }

  package var toolbarStyle: AnyToolbarStyle {
    get { self[ToolbarStyleKey.self] }
    set { self[ToolbarStyleKey.self] = newValue }
  }

  package var sheetStyle: AnySheetStyle {
    get { self[SheetStyleKey.self] }
    set { self[SheetStyleKey.self] = newValue }
  }

  package var promptStyle: AnyPromptStyle {
    get { self[PromptStyleKey.self] }
    set { self[PromptStyleKey.self] = newValue }
  }

  package var fullScreenCoverStyle: AnyFullScreenCoverStyle {
    get { self[FullScreenCoverStyleKey.self] }
    set { self[FullScreenCoverStyleKey.self] = newValue }
  }

  package var popoverStyle: AnyPopoverStyle {
    get { self[PopoverStyleKey.self] }
    set { self[PopoverStyleKey.self] = newValue }
  }

  package var tabViewStyle: AnyTabViewStyle {
    get { self[TabViewStyleKey.self] }
    set { self[TabViewStyleKey.self] = newValue }
  }

  /// The indicator visibility for the vertical axis. Set both axes with
  /// ``View/scrollIndicators(_:axes:)``.
  public var scrollIndicatorVisibility: ScrollIndicatorVisibility {
    get { self[ScrollIndicatorVisibilityKey.self] }
    set { self[ScrollIndicatorVisibilityKey.self] = newValue }
  }

  /// The indicator visibility for the horizontal axis.
  package var horizontalScrollIndicatorVisibility: ScrollIndicatorVisibility {
    get { self[HorizontalScrollIndicatorVisibilityKey.self] }
    set { self[HorizontalScrollIndicatorVisibilityKey.self] = newValue }
  }

  public var tableHeaderVisibility: TableHeaderVisibility {
    get { self[TableHeaderVisibilityKey.self] }
    set { self[TableHeaderVisibilityKey.self] = newValue }
  }

  package var theme: Theme? {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
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
    get {
      // The containment bake: a reader's value can flip when focus moves
      // anywhere in its ancestor/descendant cone, so bake readers need the
      // WHOLESALE focus-move coverage — record the runtime focus dependency
      // (the same key `@Environment(\.isFocused)` maps to), not just the
      // side-field sentinel.
      MainActor.assumeIsolated {
        ViewNodeContext.current?.recordEnvironmentRead(
          ObjectIdentifier(FocusedIdentityKey.self)
        )
      }
      return _isFocused
    }
    set { _isFocused = newValue }
  }

  public var isFocusEffectEnabled: Bool {
    get { self[IsFocusEffectEnabledKey.self] }
    set { self[IsFocusEffectEnabledKey.self] = newValue }
  }

  package var focusedIdentity: Identity? {
    get {
      recordRuntimeFocusSideFieldRead()
      return _focusedIdentity
    }
    set { _focusedIdentity = newValue }
  }

  package var pressedIdentity: Identity? {
    get {
      recordRuntimeFocusSideFieldRead()
      return _pressedIdentity
    }
    set { _pressedIdentity = newValue }
  }

  /// Side-field reads are attributed to the evaluating node (mirroring the
  /// keyed subscript) under the sentinel key. Framework readers compare
  /// these fields against identities at or below themselves, so a focus
  /// move's recompute cone only needs the readers on the moved identity's
  /// root path — the predicate `ViewGraph.hasRuntimeFocusReaderOnPath`
  /// consumes this attribution. Infrastructure reads (the context bake and
  /// override plumbing) use the raw `_focusedIdentity` field instead, so
  /// they do not flag every node.
  private func recordRuntimeFocusSideFieldRead() {
    MainActor.assumeIsolated {
      ViewNodeContext.current?.recordEnvironmentRead(
        Self.runtimeFocusSideFieldReadDependencyKey
      )
    }
  }

  /// Target-scoped side-field read: the caller declares the EXACT identities
  /// its comparisons target (all at or below itself, per the framework read
  /// audit — a reader comparing against anything else must use the plain
  /// `focusedIdentity` getter). Records the target-scoped sentinel plus the
  /// declared targets on the evaluating node; the focus-move predicates then
  /// treat this reader as affected only when the moved identity is among the
  /// targets, so its presence on a content descendant's root path does not
  /// block that descendant's chrome-only demotion. This matters doubly for
  /// controls resolved as value-only children (no own view node): their
  /// reads land on the nearest evaluated ANCESTOR node, and one broad read
  /// there would re-broaden every focus move inside that whole subtree.
  package func focusedIdentity(
    comparedAgainst targets: Set<Identity>
  ) -> Identity? {
    recordTargetScopedRuntimeFocusRead(targets)
    return _focusedIdentity
  }

  /// The `pressedIdentity` counterpart of
  /// ``focusedIdentity(comparedAgainst:)`` — controls compare the pressed
  /// side-field against themselves for press chrome.
  package func pressedIdentity(
    comparedAgainst targets: Set<Identity>
  ) -> Identity? {
    recordTargetScopedRuntimeFocusRead(targets)
    return _pressedIdentity
  }

  private func recordTargetScopedRuntimeFocusRead(
    _ targets: Set<Identity>
  ) {
    MainActor.assumeIsolated {
      if let reader = ViewNodeContext.current {
        reader.recordEnvironmentRead(
          Self.runtimeFocusTargetScopedReadDependencyKey
        )
        reader.recordFocusComparisonTargets(targets)
      }
    }
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
      theme: theme,
      foregroundStyle: foregroundStyle,
      tintStyle: tintStyle,
      isEnabled: isEnabled
    )
  }

}
