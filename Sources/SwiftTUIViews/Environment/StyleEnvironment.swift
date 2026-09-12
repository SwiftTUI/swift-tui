public import SwiftTUICore

private enum LinkStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyLinkStyle.automatic
}

private enum ScrollViewStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyScrollViewStyle.automatic
}

private enum SliderStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnySliderStyle.automatic
}

private enum StepperStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyStepperStyle.automatic
}

enum ThemeKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: Theme? = nil
}

private enum ForegroundStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: AnyShapeStyle? = nil
}

private enum TintStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: AnyShapeStyle? = nil
}

private enum TerminalAppearanceKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = TerminalAppearance.fallback
}

private enum TerminalSizeKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = CellSize(width: 80, height: 24)
}

private enum SafeAreaInsetsKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = EdgeInsets.zero
}

private enum ControlProminenceKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = ControlProminence.standard
}

private enum ButtonBorderShapeKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = ButtonBorderShape.automatic
}

private enum ButtonStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyButtonStyle.automatic
}

private enum ToggleStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyToggleStyle.automatic
}

private enum DisclosureGroupStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyDisclosureGroupStyle.automatic
}

private enum TextEditorStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyTextEditorStyle.automatic
}

private enum ProgressViewStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyProgressViewStyle.automatic
}

private enum LabelStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyLabelStyle.automatic
}

private enum LabeledContentStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyLabeledContentStyle.automatic
}

private enum ControlGroupStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyControlGroupStyle.automatic
}

private enum MenuStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyMenuStyle.automatic
}

private enum PaletteStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyPaletteStyle.automatic
}

private enum GroupBoxStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyGroupBoxStyle.automatic
}

private enum TextFieldStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = AnyTextFieldStyle.automatic
}

private enum PickerStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = AnyPickerStyle.automatic
}

private enum ListStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyListStyle.automatic
}

private enum TableStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyTableStyle.automatic
}

private enum SpinnerStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnySpinnerStyle.automatic
}

private enum ToolbarStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyToolbarStyle.defaultTop
}

private enum SheetStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnySheetStyle.automatic
}

private enum PromptStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyPromptStyle.automatic
}

private enum FullScreenCoverStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyFullScreenCoverStyle.automatic
}

private enum PopoverStyleKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = AnyPopoverStyle.automatic
}

private enum TabViewStyleKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = AnyTabViewStyle.automatic
}

private enum ScrollIndicatorVisibilityKey: EnvironmentKey, ReaderAttributedFrameworkEnvironmentKey {
  static let defaultValue = ScrollIndicatorVisibility.automatic
}

private enum HorizontalScrollIndicatorVisibilityKey: EnvironmentKey,
  ReaderAttributedFrameworkEnvironmentKey
{
  static let defaultValue = ScrollIndicatorVisibility.automatic
}

private enum TableHeaderVisibilityKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = TableHeaderVisibility.automatic
}

private enum IsEnabledKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = true
}

private enum FocusedIdentityKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: Identity? = nil
}

private enum PressedIdentityKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: Identity? = nil
}

private enum IsFocusEffectEnabledKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue = true
}

private enum PickerViewportLineCountKey: EnvironmentKey, FrameworkEnvironmentKey {
  static let defaultValue: Int? = nil
}

private enum PickerLineWidthKey: EnvironmentKey, FrameworkEnvironmentKey {
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

  /// The detected appearance of the host terminal.
  ///
  /// Carries the terminal's foreground, background, and tint colors, its ANSI
  /// palette, the derived contrast level, and how the value was determined.
  /// The host writes the live value near the scene root; without a host it is
  /// `TerminalAppearance.fallback`.
  ///
  /// A style rarely reads this key directly, because every style
  /// configuration already carries the same value as
  /// `StyleEnvironmentSnapshot.appearance`, and the semantic `Theme`
  /// derived from it is usually the better source of paints.
  ///
  /// See <doc:Styling-And-Theming>.
  public var terminalAppearance: TerminalAppearance {
    get { self[TerminalAppearanceKey.self] }
    set { self[TerminalAppearanceKey.self] = newValue }
  }

  /// The size of the terminal surface in cells.
  ///
  /// This is the whole surface, not the space proposed to the reading view;
  /// use a layout proposal or `GeometryReader` for that. Presentation styles
  /// read it to size sheets, prompts, and covers against the screen. Defaults
  /// to 80 by 24 cells when no host has reported a size.
  ///
  /// See <doc:Geometry-And-Preferences>.
  public var terminalSize: CellSize {
    get { self[TerminalSizeKey.self] }
    set { self[TerminalSizeKey.self] = newValue }
  }

  /// The insets, in cells, that host chrome reserves at the edges of the
  /// terminal surface.
  ///
  /// Zero on a plain terminal host. A host that reserves edge cells, such as
  /// one drawing its own status line, writes them here so full-surface
  /// content can stay clear of them.
  ///
  /// See <doc:Geometry-And-Preferences>.
  public var safeAreaInsets: EdgeInsets {
    get { self[SafeAreaInsetsKey.self] }
    set { self[SafeAreaInsetsKey.self] = newValue }
  }

  /// The contrast level of the detected terminal appearance.
  ///
  /// Derived from ``EnvironmentValues/terminalAppearance`` rather than stored,
  /// so it cannot be written on its own. `ColorSchemeContrast.increased`
  /// means the terminal's foreground and background are far enough apart that
  /// styles should prefer stronger separation over subtle tinting.
  ///
  /// See <doc:Styling-And-Theming>.
  public var colorSchemeContrast: ColorSchemeContrast {
    terminalAppearance.colorSchemeContrast
  }

  /// The emphasis level controls in this subtree render with.
  ///
  /// Written with `controlProminence(_:)` and defaulting to
  /// `ControlProminence.standard`. Built-in chrome reads it to choose between
  /// a neutral surface and a filled accent one; a style receives it through
  /// its configuration and is free to ignore it.
  ///
  /// See <doc:Style-System>.
  public var controlProminence: ControlProminence {
    get { self[ControlProminenceKey.self] }
    set { self[ControlProminenceKey.self] = newValue }
  }

  /// The border geometry bordered buttons in this subtree ask for.
  ///
  /// Written with `buttonBorderShape(_:)` and defaulting to
  /// `ButtonBorderShape.automatic`, which leaves the choice to the style. It
  /// reaches a ``ButtonStyle`` through
  /// ``ButtonStyleConfiguration/buttonBorderShape``.
  ///
  /// See <doc:Style-System>.
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

  /// Whether tables in this subtree show their header row.
  ///
  /// Written with `tableHeaders(_:)` and defaulting to
  /// `TableHeaderVisibility.automatic`, which leaves the decision to the
  /// table. The resolved value reaches a ``TableStyle`` through
  /// ``TableStyleConfiguration/showsHeaders``.
  ///
  /// See <doc:Collections>.
  public var tableHeaderVisibility: TableHeaderVisibility {
    get { self[TableHeaderVisibilityKey.self] }
    set { self[TableHeaderVisibilityKey.self] = newValue }
  }

  package var theme: Theme? {
    get { self[ThemeKey.self] }
    set { self[ThemeKey.self] = newValue }
  }

  /// The ambient foreground paint, or `nil` when none is set.
  ///
  /// Written with `foregroundStyle(_:)`. It reaches a style as
  /// `StyleEnvironmentSnapshot.foregroundStyle` and overrides the
  /// `.foreground` semantic role in
  /// `StyleEnvironmentSnapshot.resolvedStyle(for:)`, so a style that
  /// resolves paints through that method inherits an app-level override
  /// without extra work. `nil` means the theme decides.
  ///
  /// See <doc:Styling-And-Theming>.
  public var foregroundStyle: AnyShapeStyle? {
    get { self[ForegroundStyleKey.self] }
    set { self[ForegroundStyleKey.self] = newValue }
  }

  /// The ambient tint paint, or `nil` when none is set.
  ///
  /// Written with `tint(_:)`. It reaches a style as
  /// `StyleEnvironmentSnapshot.tintStyle` and overrides the `.tint` semantic
  /// role in `StyleEnvironmentSnapshot.resolvedStyle(for:)`, so accent
  /// chrome such as a focused border follows it. `nil` means the theme
  /// decides.
  ///
  /// See <doc:Styling-And-Theming>.
  public var tintStyle: AnyShapeStyle? {
    get { self[TintStyleKey.self] }
    set { self[TintStyleKey.self] = newValue }
  }

  /// Whether controls in this subtree accept interaction.
  ///
  /// Written with `disabled(_:)`, which combines with ancestor values rather
  /// than replacing them, so a nested `disabled(false)` cannot re-enable a
  /// disabled subtree. A disabled control registers no activation handler, and
  /// the value reaches a style as `StyleEnvironmentSnapshot.isEnabled`.
  /// Defaults to `true`.
  ///
  /// See <doc:Forms-And-Controls>.
  public var isEnabled: Bool {
    get { self[IsEnabledKey.self] }
    set { self[IsEnabledKey.self] = newValue }
  }

  /// Whether focus is currently on the reading view or anywhere inside it.
  ///
  /// The value is baked per node from the runtime focus identity, so a
  /// container reads `true` while any descendant holds focus. Reading it
  /// registers a dependency on focus movement, which widens the subtree
  /// recomputed when focus moves; prefer the focus state a control's style
  /// configuration already carries when one is available.
  ///
  /// See <doc:Focus>.
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

  /// Whether focused controls in this subtree draw a focus effect.
  ///
  /// Defaults to `true`. Setting it to `false` suppresses the visual
  /// treatment only: the control still takes focus, still receives keyboard
  /// input, and still reports its focus state. Built-in styles combine it
  /// with the focus state, which a ``ButtonStyle`` sees as
  /// ``ButtonStyleConfiguration/showsFocusEffect``.
  ///
  /// See <doc:Focus>.
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
      isEnabled: isEnabled,
      cellPixelMetrics: cellPixelMetrics
    )
  }

}
