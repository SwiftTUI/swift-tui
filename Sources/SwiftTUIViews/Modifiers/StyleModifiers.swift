public import SwiftTUICore

extension View {
  /// Sets the style that command palettes use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every command palette
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyPaletteStyle/automatic``, which supplies a filter field with fuzzy
  /// matching, a selectable command list, and Return to run the selection.
  ///
  /// A palette reads the value when a `paletteSheet(_:isPresented:)`
  /// declaration presents. This overload erases to `some View`, which drops an
  /// `ActionScope` conformance; use the `ActionScope` overload of
  /// `paletteStyle(_:)` when a `paletteSheet(_:isPresented:)` has to follow.
  ///
  /// ```swift
  /// ContentView().paletteStyle(.automatic)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func paletteStyle(_ style: AnyPaletteStyle) -> some View {
    environment(\.paletteStyle, style)
  }
  /// Sets the style that command palettes use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyPaletteStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``PaletteStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func paletteStyle<S: PaletteStyle>(_ style: S) -> some View {
    paletteStyle(AnyPaletteStyle(style))
  }

  /// Sets the style that scroll views use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every scroll view
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyScrollViewStyle/automatic`` (indicators drawn beside the content)
  /// and ``AnyScrollViewStyle/minimal``.
  ///
  /// The style supplies indicator glyphs, paints, insets, and track
  /// reservation. Indicator visibility itself stays with
  /// `scrollIndicators(_:axes:)`; the style sees the resolved visibility and
  /// cannot override it.
  ///
  /// ```swift
  /// ScrollView { rows }
  ///   .scrollViewStyle(.minimal)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func scrollViewStyle(_ style: AnyScrollViewStyle) -> some View {
    environment(\.scrollViewStyle, style)
  }

  /// Sets the style that scroll views use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyScrollViewStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ScrollViewStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func scrollViewStyle<S: ScrollViewStyle>(_ style: S) -> some View {
    scrollViewStyle(AnyScrollViewStyle(style))
  }

  /// Sets the style that links use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every link
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyLinkStyle/automatic``, ``AnyLinkStyle/underlined``, and
  /// ``AnyLinkStyle/plain``.
  ///
  /// This covers standalone `Link` views and links interpolated into a
  /// ``Text``. For an interpolated link, apply the modifier to the containing
  /// ``Text`` so the run keeps its formatting. The style returns paints,
  /// emphasis, opacity, and underline treatment per interaction state; it does
  /// not decide what activation does, which stays with
  /// `openLinkAction(_:)`.
  ///
  /// ```swift
  /// Link("Docs", destination: url)
  ///   .linkStyle(.underlined)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func linkStyle(_ style: AnyLinkStyle) -> some View {
    environment(\.linkStyle, style)
  }

  /// Sets the style that links use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyLinkStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``LinkStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func linkStyle<S: LinkStyle>(_ style: S) -> some View {
    linkStyle(AnyLinkStyle(style))
  }

  /// Sets the style that sliders use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every slider
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnySliderStyle/automatic``, a fixed alias of
  /// ``AnySliderStyle/linear``.
  ///
  /// The style composes the label, the value label, and the track from the
  /// normalized fraction. The value binding, keyboard adjustment, and focus
  /// stop stay with the ``Slider`` primitive.
  ///
  /// ```swift
  /// Slider(value: $volume)
  ///   .sliderStyle(.linear)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func sliderStyle(_ style: AnySliderStyle) -> some View {
    environment(\.sliderStyle, style)
  }
  /// Sets the style that sliders use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnySliderStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``SliderStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func sliderStyle<S: SliderStyle>(_ style: S) -> some View {
    sliderStyle(AnySliderStyle(style))
  }

  /// Sets the style that steppers use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every stepper
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyStepperStyle/automatic`` and ``AnyStepperStyle/compact``.
  ///
  /// The style composes the label, the value label, and the increment and
  /// decrement affordances. Bound-limit enforcement, keyboard adjustment, and
  /// the focus stop stay with the ``Stepper`` primitive.
  ///
  /// ```swift
  /// Stepper(value: $count, in: 0...9) { Text("Count") }
  ///   .stepperStyle(.compact)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func stepperStyle(_ style: AnyStepperStyle) -> some View {
    environment(\.stepperStyle, style)
  }
  /// Sets the style that steppers use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyStepperStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``StepperStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func stepperStyle<S: StepperStyle>(_ style: S) -> some View {
    stepperStyle(AnyStepperStyle(style))
  }

  /// Sets the style that toggles use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every toggle
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyToggleStyle/automatic``, ``AnyToggleStyle/checkbox``, and
  /// ``AnyToggleStyle/button``.
  ///
  /// The style composes the label and the on/off indicator. The `isOn`
  /// binding reaches the style through the configuration and cannot be
  /// replaced; activation, focus, and semantics stay with the ``Toggle``
  /// primitive.
  ///
  /// ```swift
  /// Toggle("Wrap lines", isOn: $wraps)
  ///   .toggleStyle(.checkbox)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func toggleStyle(_ style: AnyToggleStyle) -> some View {
    environment(\.toggleStyle, style)
  }

  /// Sets the style that toggles use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyToggleStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ToggleStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
    toggleStyle(AnyToggleStyle(style))
  }

  /// Sets the style that disclosure groups use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every disclosure group
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyDisclosureGroupStyle/automatic`` and
  /// ``AnyDisclosureGroupStyle/compact``.
  ///
  /// The style composes the label, the disclosure indicator, and the expanded
  /// content. The `isExpanded` binding reaches the style through the
  /// configuration and cannot be replaced.
  ///
  /// ```swift
  /// DisclosureGroup("Advanced") { settings }
  ///   .disclosureGroupStyle(.compact)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func disclosureGroupStyle(_ style: AnyDisclosureGroupStyle) -> some View {
    environment(\.disclosureGroupStyle, style)
  }

  /// Sets the style that disclosure groups use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyDisclosureGroupStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``DisclosureGroupStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View {
    disclosureGroupStyle(AnyDisclosureGroupStyle(style))
  }

  /// Sets the style that text editors use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every text editor
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyTextEditorStyle/automatic`` (which renders as
  /// ``AnyTextEditorStyle/roundedBorder``) and ``AnyTextEditorStyle/plain``.
  ///
  /// The style wraps chrome around the editor content, which reaches it as a
  /// protected slot: placing that slot in the body preserves the editing
  /// surface, its cursor, and its text binding.
  ///
  /// ```swift
  /// TextEditor(text: $draft)
  ///   .textEditorStyle(.plain)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func textEditorStyle(_ style: AnyTextEditorStyle) -> some View {
    environment(\.textEditorStyle, style)
  }

  /// Sets the style that text editors use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyTextEditorStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``TextEditorStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func textEditorStyle<S: TextEditorStyle>(_ style: S) -> some View {
    textEditorStyle(AnyTextEditorStyle(style))
  }

  /// Sets the style that progress views use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every progress view
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyProgressViewStyle/automatic`` (which renders as
  /// ``AnyProgressViewStyle/linear``) and ``AnyProgressViewStyle/circular``.
  ///
  /// The style composes the optional label and current-value label with the
  /// completed fraction. A determinate progress view hands the style a
  /// fraction; an indeterminate one hands it `nil` plus an animation phase.
  ///
  /// ```swift
  /// ProgressView(value: fraction)
  ///   .progressViewStyle(.circular)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func progressViewStyle(_ style: AnyProgressViewStyle) -> some View {
    environment(\.progressViewStyle, style)
  }

  /// Sets the style that progress views use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyProgressViewStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ProgressViewStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
    progressViewStyle(AnyProgressViewStyle(style))
  }

  /// Sets the style that labels use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every label
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyLabelStyle/automatic`` (which renders as
  /// ``AnyLabelStyle/titleAndIcon``), ``AnyLabelStyle/titleOnly``, and
  /// ``AnyLabelStyle/iconOnly``.
  ///
  /// The style receives the authored title and icon as separate slots and
  /// decides which to place and how to space them. Omitting a slot hides that
  /// content without removing it from the accessibility description.
  ///
  /// ```swift
  /// Label("Save", systemImage: "arrow.down")
  ///   .labelStyle(.iconOnly)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func labelStyle(_ style: AnyLabelStyle) -> some View {
    environment(\.labelStyle, style)
  }

  /// Sets the style that labels use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyLabelStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``LabelStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
    labelStyle(AnyLabelStyle(style))
  }

  /// Sets the style that labeled content views use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every labeled content view
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyLabeledContentStyle/automatic`` (label and value on one row) and
  /// ``AnyLabeledContentStyle/stacked``.
  ///
  /// The style receives the authored label and value as separate slots and
  /// arranges them. Both slots keep the state and environment of where they
  /// were written.
  ///
  /// ```swift
  /// LabeledContent("Host") { Text(host) }
  ///   .labeledContentStyle(.stacked)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func labeledContentStyle(_ style: AnyLabeledContentStyle) -> some View {
    environment(\.labeledContentStyle, style)
  }

  /// Sets the style that labeled content views use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyLabeledContentStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``LabeledContentStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View {
    labeledContentStyle(AnyLabeledContentStyle(style))
  }

  /// Sets the style that control groups use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every control group
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyControlGroupStyle/automatic`` (a fixed alias of
  /// ``AnyControlGroupStyle/horizontal``), ``AnyControlGroupStyle/vertical``,
  /// and ``AnyControlGroupStyle/compactMenu``.
  ///
  /// The style arranges the authored controls and the optional label. The
  /// grouped controls keep their own state and focus stops wherever the style
  /// places them.
  ///
  /// ```swift
  /// ControlGroup { buttons }
  ///   .controlGroupStyle(.vertical)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func controlGroupStyle(_ style: AnyControlGroupStyle) -> some View {
    environment(\.controlGroupStyle, style)
  }

  /// Sets the style that control groups use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyControlGroupStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ControlGroupStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func controlGroupStyle<S: ControlGroupStyle>(_ style: S) -> some View {
    controlGroupStyle(AnyControlGroupStyle(style))
  }

  /// Sets the style that menus use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every menu
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyMenuStyle/automatic``, ``AnyMenuStyle/button``,
  /// ``AnyMenuStyle/borderlessButton``, and ``AnyMenuStyle/inline``.
  ///
  /// The style composes the trigger and the menu content, marking them with
  /// the configuration's `trigger` and `portal(presentation:)` wrappers. While
  /// the menu is presented, the body must either place the content inline or
  /// install the portal wrapper. A body that does neither reports
  /// `style.missingRequiredRoute` and ``AnyMenuStyle/automatic`` renders for
  /// that resolve. The `isPresented` binding and keyboard activation stay with
  /// the ``Menu`` primitive.
  ///
  /// ```swift
  /// Menu("Actions") { items }
  ///   .menuStyle(.borderlessButton)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func menuStyle(_ style: AnyMenuStyle) -> some View {
    environment(\.menuStyle, style)
  }

  /// Sets the style that menus use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyMenuStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``MenuStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func menuStyle<S: MenuStyle>(_ style: S) -> some View {
    menuStyle(AnyMenuStyle(style))
  }

  /// Sets the style that group boxes use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every group box
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyGroupBoxStyle/automatic`` (which renders as
  /// ``AnyGroupBoxStyle/bordered``) and ``AnyGroupBoxStyle/plain``.
  ///
  /// The style composes the optional label with the grouped content and draws
  /// the surrounding chrome. It also reads the ambient control prominence, so
  /// `controlProminence(.increased)` moves the built-in border to the theme
  /// accent tone.
  ///
  /// ```swift
  /// GroupBox { form } label: { Text("Server") }
  ///   .groupBoxStyle(.plain)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func groupBoxStyle(_ style: AnyGroupBoxStyle) -> some View {
    environment(\.groupBoxStyle, style)
  }

  /// Sets the style that group boxes use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyGroupBoxStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``GroupBoxStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func groupBoxStyle<S: GroupBoxStyle>(_ style: S) -> some View {
    groupBoxStyle(AnyGroupBoxStyle(style))
  }

  /// Sets the emphasis level that controls in this subtree render with.
  ///
  /// The value is stored in the environment and the nearest modifier wins.
  /// `ControlProminence.standard` is the default; `.increased` asks built-in
  /// chrome for a filled accent surface instead of a neutral one, and reaches
  /// a custom style through its configuration.
  ///
  /// ```swift
  /// Button("Install") { install() }
  ///   .buttonStyle(.borderedProminent)
  ///   .controlProminence(.increased)
  /// ```
  ///
  /// - Parameter prominence: The emphasis level for the subtree.
  ///
  /// See <doc:Style-System> and <doc:Styling-And-Theming>.
  public func controlProminence(
    _ prominence: ControlProminence
  ) -> some View {
    environment(\.controlProminence, prominence)
  }

  /// Sets the border geometry that bordered buttons in this subtree use.
  ///
  /// The value is stored in the environment and the nearest modifier wins.
  /// `ButtonBorderShape.automatic` lets the style pick; `.roundedRectangle`
  /// asks for rounded border glyphs. The value reaches a custom
  /// ``ButtonStyle`` through ``ButtonStyleConfiguration/buttonBorderShape``,
  /// so a style is free to ignore it.
  ///
  /// ```swift
  /// Button("Cancel", role: .cancel) { dismiss() }
  ///   .buttonStyle(.bordered)
  ///   .buttonBorderShape(.roundedRectangle)
  /// ```
  ///
  /// - Parameter shape: The border geometry for bordered buttons.
  ///
  /// See <doc:Style-System>.
  public func buttonBorderShape(
    _ shape: ButtonBorderShape
  ) -> some View {
    environment(\.buttonBorderShape, shape)
  }

  /// Sets the style that buttons use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every button
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyButtonStyle/automatic``, ``AnyButtonStyle/plain``,
  /// ``AnyButtonStyle/bordered``, ``AnyButtonStyle/borderedProminent``, and
  /// ``AnyButtonStyle/link``.
  ///
  /// The style composes the authored label with the button's render state:
  /// role, enabled, focused, pressed, and the ambient control prominence and
  /// button border shape. Activation, the focus stop, keyboard handling, and
  /// accessibility semantics stay with the ``Button`` primitive.
  ///
  /// ```swift
  /// VStack { actions }
  ///   .buttonStyle(.bordered)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func buttonStyle(
    _ style: AnyButtonStyle
  ) -> some View {
    environment(\.buttonStyle, style)
  }

  /// Sets the style that buttons use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyButtonStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ButtonStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func buttonStyle<S: ButtonStyle>(
    _ style: S
  ) -> some View {
    buttonStyle(AnyButtonStyle(style))
  }

  /// Sets the style that text fields use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every text field
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyTextFieldStyle/automatic`` (which renders as
  /// ``AnyTextFieldStyle/roundedBorder``) and ``AnyTextFieldStyle/plain``.
  ///
  /// This covers both ``TextField`` and ``SecureField``. The editable field
  /// reaches the style as a protected slot: placing it in the body keeps the
  /// text binding, the cursor, and the field's keyboard handling. The style
  /// supplies chrome, the optional label, and the prompt treatment.
  ///
  /// ```swift
  /// Form { fields }
  ///   .textFieldStyle(.roundedBorder)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func textFieldStyle(
    _ style: AnyTextFieldStyle
  ) -> some View {
    environment(\.textFieldStyle, style)
  }

  /// Sets the style that text fields use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyTextFieldStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``TextFieldStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func textFieldStyle<S: TextFieldStyle>(
    _ style: S
  ) -> some View {
    textFieldStyle(AnyTextFieldStyle(style))
  }

  /// Sets the style that pickers use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every picker
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyPickerStyle/automatic`` (which renders as
  /// ``AnyPickerStyle/inline``), ``AnyPickerStyle/segmented``,
  /// ``AnyPickerStyle/radioGroup``, and ``AnyPickerStyle/menu``.
  ///
  /// The style composes the label and the option rows, each of which carries
  /// its index, label, selected flag, and enabled flag. Selection is written
  /// through the configuration rather than by the style: a style reports where
  /// a pointer landed with the option's route wrapper and moves the selection
  /// with `selectionDelta(for:)`. The selection binding stays with the
  /// ``Picker`` primitive.
  ///
  /// ```swift
  /// Picker("Theme", selection: $theme) { options }
  ///   .pickerStyle(.segmented)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func pickerStyle(
    _ style: AnyPickerStyle
  ) -> some View {
    environment(\.pickerStyle, style)
  }

  /// Sets the style that pickers use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyPickerStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``PickerStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func pickerStyle<S: PickerStyle>(
    _ style: S
  ) -> some View {
    pickerStyle(AnyPickerStyle(style))
  }

  /// Sets the style that lists use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every list
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyListStyle/automatic`` (a fixed alias of
  /// ``AnyListStyle/insetGrouped``) and ``AnyListStyle/plain``.
  ///
  /// ``ListStyle`` is a presentation-value family: the style returns the
  /// container chrome, the scope it is painted at, the content insets, and
  /// whether row and section separators are drawn. The ``List`` primitive
  /// keeps row identity, selection, focus, and scrolling. Per-row overrides
  /// come from
  /// `listRowBackground(_:)`, `listRowForegroundStyle(_:)`,
  /// `listRowSeparator(_:edges:)`, and `listSectionSeparator(_:edges:)`.
  ///
  /// ```swift
  /// List(rows) { row in Text(row.title) }
  ///   .listStyle(.plain)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func listStyle(
    _ style: AnyListStyle
  ) -> some View {
    environment(\.listStyle, style)
  }

  /// Sets the style that lists use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyListStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ListStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func listStyle<S: ListStyle>(
    _ style: S
  ) -> some View {
    listStyle(AnyListStyle(style))
  }

  /// Sets the style that tables use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every table
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyTableStyle/automatic`` (a fixed alias of
  /// ``AnyTableStyle/inset``) and ``AnyTableStyle/bordered``.
  ///
  /// ``TableStyle`` is a presentation-value family: the style sees the column
  /// count, whether headers show, and the selection and focus state, and
  /// returns rules, insets, and paints. Header visibility itself is set with
  /// `tableHeaders(_:)`.
  ///
  /// ```swift
  /// Table(columns: columns) { rows }
  ///   .tableStyle(.bordered)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func tableStyle(
    _ style: AnyTableStyle
  ) -> some View {
    environment(\.tableStyle, style)
  }

  /// Sets the style that tables use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyTableStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``TableStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func tableStyle<S: TableStyle>(
    _ style: S
  ) -> some View {
    tableStyle(AnyTableStyle(style))
  }

  /// Sets the style that spinners use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every spinner
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnySpinnerStyle/automatic``, the braille loop at 64 ms with inherited
  /// foreground, plus 37 further glyph presets such as
  /// ``AnySpinnerStyle/barRise``, ``AnySpinnerStyle/clockFace``, and
  /// ``AnySpinnerStyle/moonPhase``.
  ///
  /// ``SpinnerStyle`` is a presentation-value family: the style maps the
  /// spinner's stage and the reduce-motion setting to frames, a frame
  /// interval, and a paint. An invalid presentation reports
  /// `style.invalidPresentation` and the automatic presentation renders
  /// instead of trapping: invalid means an empty frame list, a non-positive
  /// interval, or frames that mix terminal-cell widths.
  ///
  /// ```swift
  /// Spinner()
  ///   .spinnerStyle(.moonPhase)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func spinnerStyle(
    _ style: AnySpinnerStyle
  ) -> some View {
    environment(\.spinnerStyle, style)
  }

  /// Sets the style that spinners use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnySpinnerStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``SpinnerStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func spinnerStyle<S: SpinnerStyle>(
    _ style: S
  ) -> some View {
    spinnerStyle(AnySpinnerStyle(style))
  }

  /// Sets the style that sheets use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every sheet
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnySheetStyle/automatic`` (a fixed alias of ``AnySheetStyle/surface``)
  /// and ``AnySheetStyle/dropdown``.
  ///
  /// A `sheet(...)` declaration reads the nearest value when it presents, so
  /// this may sit on the declaration or on any ancestor. ``SheetStyle`` is a
  /// presentation-value family: the style adjusts insets, alignment, chrome,
  /// and backdrop from a baseline presentation, the terminal size, and the
  /// ambient control prominence. An invalid presentation reports
  /// `style.invalidPresentation` and the baseline is used instead.
  ///
  /// ```swift
  /// ContentView()
  ///   .sheetStyle(.dropdown)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func sheetStyle(
    _ style: AnySheetStyle
  ) -> some View {
    environment(\.sheetStyle, style)
  }

  /// Sets the style that sheets use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnySheetStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``SheetStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func sheetStyle<S: SheetStyle>(
    _ style: S
  ) -> some View {
    sheetStyle(AnySheetStyle(style))
  }

  /// Sets the style that alerts and confirmation dialogs use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every alert or confirmation dialog
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyPromptStyle/automatic``.
  ///
  /// An `alert(...)` or `confirmationDialog(...)` declaration reads the
  /// nearest value when it presents. ``PromptStyle`` is a presentation-value
  /// family: the style sees whether the prompt has a message and actions, plus
  /// a baseline presentation, and returns insets, alignment, and backdrop
  /// opacity. Action ordering, dismissal, and the default dismiss button stay
  /// with the declaration.
  ///
  /// ```swift
  /// ContentView()
  ///   .promptStyle(.automatic)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func promptStyle(_ style: AnyPromptStyle) -> some View {
    environment(\.promptStyle, style)
  }

  /// Sets the style that alerts and confirmation dialogs use, from a concrete
  /// style.
  ///
  /// Equivalent to wrapping `style` in ``AnyPromptStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``PromptStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func promptStyle<S: PromptStyle>(_ style: S) -> some View {
    promptStyle(AnyPromptStyle(style))
  }

  /// Sets the style that full-screen covers use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every full-screen cover
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyFullScreenCoverStyle/automatic``.
  ///
  /// A `fullScreenCover(...)` declaration reads the nearest value when it
  /// presents. ``FullScreenCoverStyle`` is a presentation-value family: the
  /// style returns the cover's insets and background paint. An invalid
  /// presentation reports `style.invalidPresentation` and the baseline is used
  /// instead.
  ///
  /// ```swift
  /// ContentView()
  ///   .fullScreenCoverStyle(.automatic)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func fullScreenCoverStyle(_ style: AnyFullScreenCoverStyle) -> some View {
    environment(\.fullScreenCoverStyle, style)
  }

  /// Sets the style that full-screen covers use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyFullScreenCoverStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``FullScreenCoverStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func fullScreenCoverStyle<S: FullScreenCoverStyle>(_ style: S) -> some View {
    fullScreenCoverStyle(AnyFullScreenCoverStyle(style))
  }

  /// Sets the style that popovers use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every popover
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyPopoverStyle/automatic``.
  ///
  /// A `popover(...)` declaration reads the nearest value when it presents.
  /// ``PopoverStyle`` is a presentation-value family returning an
  /// ``AnchoredSurfaceStylePresentation``: surface chrome plus the anchoring
  /// and arrow treatment. Anchor geometry and dismissal stay with the
  /// declaration.
  ///
  /// ```swift
  /// ContentView()
  ///   .popoverStyle(.automatic)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func popoverStyle(_ style: AnyPopoverStyle) -> some View {
    environment(\.popoverStyle, style)
  }

  /// Sets the style that popovers use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyPopoverStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``PopoverStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func popoverStyle<S: PopoverStyle>(_ style: S) -> some View {
    popoverStyle(AnyPopoverStyle(style))
  }

  /// Sets the style that toolbars use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every toolbar
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyToolbarStyle/defaultTop`` and ``AnyToolbarStyle/defaultBottom``.
  ///
  /// A toolbar host reads the nearest value, so this may sit on the host or on
  /// any ancestor. ``AnyToolbarStyle/defaultTop`` is the environment default,
  /// the one family whose default is not named `automatic`. ``ToolbarStyle``
  /// supplies a `Layout` for the item strip plus a placement; it has no
  /// configuration and composes no body.
  ///
  /// This overload erases to `some View`, which drops an `ActionScope`
  /// conformance. Use the `ActionScope` overload of `toolbarStyle(_:)` when a
  /// `toolbar()` declaration has to follow.
  ///
  /// ```swift
  /// NavigationStack { content }
  ///   .toolbarStyle(.defaultBottom)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func toolbarStyle(
    _ style: AnyToolbarStyle
  ) -> some View {
    environment(\.toolbarStyle, style)
  }

  /// Sets the style that toolbars use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyToolbarStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``ToolbarStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func toolbarStyle<S: ToolbarStyle>(
    _ style: S
  ) -> some View {
    toolbarStyle(AnyToolbarStyle(style))
  }

  /// Sets the style that tab views use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every tab view
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyTabViewStyle/automatic`` (a fixed alias of
  /// ``AnyTabViewStyle/underline``), ``AnyTabViewStyle/literalTabs``, and
  /// ``AnyTabViewStyle/powerline``.
  ///
  /// The style both composes a body and supplies a presentation: it first
  /// returns strip metadata (strip height, the visible tab indices, and
  /// overflow), then composes the items, the overflow trigger, and the
  /// selected page. Pointer targets come from the item, overflow, and trigger
  /// route wrappers; the selection binding, dormant-tab state, and keyboard
  /// navigation stay with the ``TabView`` primitive.
  ///
  /// ```swift
  /// TabView(selection: $tab) { pages }
  ///   .tabViewStyle(.powerline)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func tabViewStyle(
    _ style: AnyTabViewStyle
  ) -> some View {
    environment(\.tabViewStyle, style)
  }

  /// Sets the style that tab views use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyTabViewStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``TabViewStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func tabViewStyle<S: TabViewStyle>(
    _ style: S
  ) -> some View {
    tabViewStyle(AnyTabViewStyle(style))
  }

  /// Sets the style that outline groups use in this subtree.
  ///
  /// The style is stored in the environment, so it reaches every outline group
  /// below this modifier, and the nearest modifier wins.
  ///
  /// Built-ins: ``AnyOutlineStyle/automatic`` (a fixed alias of
  /// ``AnyOutlineStyle/rounded``) and ``AnyOutlineStyle/plain``.
  ///
  /// ``OutlineStyle`` is a presentation-value family: the style sees only the
  /// `StyleEnvironmentSnapshot` and returns the connector glyphs and
  /// indentation used to draw the hierarchy. Expansion state, row identity,
  /// and selection stay with the ``OutlineGroup`` primitive.
  ///
  /// ```swift
  /// OutlineGroup(tree, children: \.children) { row }
  ///   .outlineStyle(.rounded)
  /// ```
  ///
  /// - Parameter style: The type-erased style to install.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func outlineStyle(
    _ style: AnyOutlineStyle
  ) -> some View {
    environment(\.outlineStyle, style)
  }

  /// Sets the style that outline groups use in this subtree, from a concrete style.
  ///
  /// Equivalent to wrapping `style` in ``AnyOutlineStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``OutlineStyle`` conformer.
  ///
  /// See <doc:Style-System> and <doc:Authoring-Styles>.
  public func outlineStyle<S: OutlineStyle>(
    _ style: S
  ) -> some View {
    outlineStyle(AnyOutlineStyle(style))
  }

  /// Sets whether scroll views in this subtree draw scroll indicators.
  ///
  /// Writes the visibility for each axis named in `axes`, leaving the other
  /// axis untouched, and the nearest write per axis wins. The value is an
  /// input to the scroll view style, which decides the glyphs and paints:
  /// `ScrollIndicatorVisibility.hidden` and `ScrollIndicatorVisibility.never`
  /// both suppress drawing, and the content stays scrollable either way.
  ///
  /// ```swift
  /// ScrollView { rows }
  ///   .scrollIndicators(.hidden, axes: .vertical)
  /// ```
  ///
  /// - Parameters:
  ///   - visibility: The indicator visibility to write.
  ///   - axes: The axes to write it for. Defaults to both axes.
  ///
  /// See <doc:Scrolling> and <doc:Style-System>.
  public func scrollIndicators(
    _ visibility: ScrollIndicatorVisibility,
    axes: Axis.Set = [.vertical, .horizontal]
  ) -> some View {
    transformEnvironment(\.self) { environment in
      if axes.contains(.vertical) {
        environment.scrollIndicatorVisibility = visibility
      }
      if axes.contains(.horizontal) {
        environment.horizontalScrollIndicatorVisibility = visibility
      }
    }
  }

  /// Sets whether tables in this subtree show their header row.
  ///
  /// The value is stored in the environment and the nearest modifier wins.
  /// `TableHeaderVisibility.automatic` leaves the decision to the table; the
  /// resolved value reaches a ``TableStyle`` through its configuration, so a
  /// style can adjust rules and insets for a headerless table.
  ///
  /// ```swift
  /// Table(columns: columns) { rows }
  ///   .tableHeaders(.hidden)
  /// ```
  ///
  /// - Parameter visibility: Whether the header row is shown.
  ///
  /// See <doc:Collections>.
  public func tableHeaders(
    _ visibility: TableHeaderVisibility
  ) -> some View {
    environment(\.tableHeaderVisibility, visibility)
  }

  /// Sets the handler that runs when a link in this subtree is activated.
  ///
  /// The action is stored in the environment and the nearest modifier wins. It
  /// receives the activated `LinkDestination` and returns whether it handled
  /// the activation; returning `false` leaves the destination unhandled. This
  /// governs behavior only. Link appearance comes from `linkStyle(_:)`.
  ///
  /// ```swift
  /// ContentView()
  ///   .openLinkAction(OpenLinkAction { destination in
  ///     router.open(destination)
  ///   })
  /// ```
  ///
  /// - Parameter action: The handler invoked on link activation.
  ///
  /// See <doc:Forms-And-Controls>.
  public func openLinkAction(
    _ action: OpenLinkAction
  ) -> some View {
    environment(\.openLinkAction, action)
  }

  /// Sets the ambient foreground paint for this subtree.
  ///
  /// The style is erased to `AnyShapeStyle` and written into the environment,
  /// so descendants that do not paint themselves explicitly use it, and the
  /// nearest modifier wins. It also overrides the `.foreground` semantic role
  /// for styles that resolve paints through
  /// `StyleEnvironmentSnapshot.resolvedStyle(for:)`, so built-in control
  /// chrome picks it up.
  ///
  /// Prefer a semantic role such as `SemanticShapeStyle.foreground` or a
  /// `TerminalChromeStyle` over a literal color, so the paint follows the
  /// active theme.
  ///
  /// ```swift
  /// VStack { rows }
  ///   .foregroundStyle(SemanticShapeStyle.muted)
  /// ```
  ///
  /// - Parameter style: The paint to use as the ambient foreground.
  ///
  /// See <doc:Styling-And-Theming>.
  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    modifier(
      EnvironmentWritingModifier(
        keyPath: \.foregroundStyle,
        value: AnyShapeStyle(style)
      )
    )
  }

  /// Sets the ambient tint paint for this subtree.
  ///
  /// The style is erased to `AnyShapeStyle` and written into the environment,
  /// and the nearest modifier wins. It overrides the `.tint` semantic role for
  /// styles that resolve paints through
  /// `StyleEnvironmentSnapshot.resolvedStyle(for:)`, so accent chrome such
  /// as a focused border or a selected row follows it.
  ///
  /// ```swift
  /// Form { fields }
  ///   .tint(.green)
  /// ```
  ///
  /// - Parameter style: The paint to use as the ambient tint.
  ///
  /// See <doc:Styling-And-Theming>.
  public func tint<S: ShapeStyle>(_ style: S) -> some View {
    modifier(
      EnvironmentWritingModifier(
        keyPath: \.tintStyle,
        value: AnyShapeStyle(style)
      )
    )
  }

  /// Sets or clears the ambient tint paint for this subtree.
  ///
  /// Passing `nil` writes no tint for the subtree, so `.tint` resolves from the
  /// theme again even when an ancestor set one. A non-`nil` value behaves like
  /// the non-optional overload.
  ///
  /// ```swift
  /// Form { fields }
  ///   .tint(isMuted ? nil : Color.green)
  /// ```
  ///
  /// - Parameter style: The tint paint, or `nil` to fall back to the theme.
  ///
  /// See <doc:Styling-And-Theming>.
  public func tint<S: ShapeStyle>(_ style: S?) -> some View {
    environment(\.tintStyle, style.map(AnyShapeStyle.init))
  }

  /// Sets how this view's drawing composites with what is already on the
  /// cells beneath it.
  ///
  /// The mode applies to the drawing this view produces, not to the
  /// environment, so it does not reach unrelated siblings. Compose it with
  /// `compositingGroup()` to blend a subtree as one layer instead of blending
  /// each of its parts separately.
  ///
  /// ```swift
  /// Rectangle().fill(.blue)
  ///   .blendMode(.multiply)
  /// ```
  ///
  /// - Parameter blendMode: The blend mode to apply.
  ///
  /// See <doc:Pointer-And-Canvas>.
  public func blendMode(_ blendMode: BlendMode) -> some View {
    modifier(DrawEffectModifier(effect: .blendMode(blendMode)))
  }

  /// Composites this view's subtree as one layer before later effects apply.
  ///
  /// Without it, an effect such as `blendMode(_:)` applied further out is
  /// evaluated against each part of the subtree in turn. Grouping first makes
  /// the subtree's own drawing settle before the outer effect sees it.
  ///
  /// ```swift
  /// ZStack { badge; label }
  ///   .compositingGroup()
  ///   .blendMode(.screen)
  /// ```
  ///
  /// See <doc:Pointer-And-Canvas>.
  public func compositingGroup() -> some View {
    modifier(DrawEffectModifier(effect: .compositingGroup))
  }

  /// Disables interaction for this subtree.
  ///
  /// Combines with any ancestor value rather than replacing it: the subtree is
  /// enabled only when no ancestor disabled it and `isDisabled` is `false`, so
  /// `disabled(false)` inside a disabled subtree does not re-enable it. The
  /// resolved value reaches controls as ``EnvironmentValues/isEnabled`` and
  /// reaches styles as `StyleEnvironmentSnapshot.isEnabled`. A disabled
  /// control registers no activation handler, so activating it does nothing,
  /// and built-in chrome paints it in the theme's placeholder color at
  /// reduced opacity.
  ///
  /// ```swift
  /// Form { fields }
  ///   .disabled(isSubmitting)
  /// ```
  ///
  /// - Parameter isDisabled: Whether to disable the subtree.
  ///
  /// See <doc:Forms-And-Controls>.
  public func disabled(_ isDisabled: Bool) -> some View {
    transformEnvironment(\.isEnabled) { isEnabled in
      isEnabled = isEnabled && !isDisabled
    }
  }

  /// Tags this view with the value a selection binding compares against.
  ///
  /// Selection containers such as ``Picker`` and ``TabView`` match a tagged
  /// child against their bound selection value. The tag also gives the child a
  /// stable identity, so a tagged tab keeps its state when the tab order
  /// changes.
  ///
  /// ```swift
  /// Picker("Theme", selection: $theme) {
  ///   Text("Dark").tag(Theme.dark)
  ///   Text("Light").tag(Theme.light)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - tag: The value this view is selected by.
  ///   - includeOptional: Whether the tag also matches an optional binding of
  ///     the same value type. Defaults to `true`.
  ///
  /// See <doc:Forms-And-Controls> and <doc:Navigation-And-Tabs>.
  public func tag<V: Hashable & Sendable>(
    _ tag: V,
    includeOptional: Bool = true
  ) -> some View {
    modifier(
      TagValueModifier(
        tag: tag,
        includeOptional: includeOptional
      )
    )
  }

  /// Fills the cells behind this view with a shape style.
  ///
  /// Equivalent to placing a filled `Rectangle` in the view's background, so
  /// it paints the view's own frame and adds no layout allocation.
  ///
  /// ```swift
  /// Text(status)
  ///   .padding(1)
  ///   .background(SemanticShapeStyle.fill)
  /// ```
  ///
  /// - Parameter style: The paint for the background cells.
  ///
  /// See <doc:Styling-And-Theming>.
  public func background<S: ShapeStyle>(_ style: S) -> some View {
    background {
      Rectangle().fill(style)
    }
  }

  /// Draws a border around this view.
  ///
  /// The default chrome is `BorderSet.rounded` in
  /// `StrokeStyle.Placement.inset` placement. The border draws into the
  /// outermost cells of the content frame without changing layout allocation.
  ///
  /// Pass `placement: .outset` to reserve additional cells outside the
  /// content frame so the border does not occlude its outermost cells.
  ///
  /// For other glyph palettes (single-line, half-block, double-line,
  /// or heavy) pass an explicit `set:`. See `BorderSet` for the
  /// full catalog.
  public func border<S: ShapeStyle>(
    _ style: S = SemanticShapeStyle.foreground,
    set: BorderSet = .rounded,
    placement: StrokeStyle.Placement = .inset,
    sides: Edge.Set = .all
  ) -> some View {
    borderModified(
      set: set,
      placement: placement,
      foreground: BorderEdgeStyle(AnyShapeStyle(style)),
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: sides
    )
  }

  /// Draws a border around this view using a per-side foreground style.
  public func border(
    _ style: BorderEdgeStyle,
    set: BorderSet = .rounded,
    placement: StrokeStyle.Placement = .inset,
    sides: Edge.Set = .all
  ) -> some View {
    borderModified(
      set: set,
      placement: placement,
      foreground: style,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: sides
    )
  }

  /// Draws a border whose foreground color is sampled continuously
  /// around the perimeter from a `BorderBlend`.
  ///
  /// The blend's stops are interpolated as the rasterizer walks the
  /// rectangle's edges clockwise (top L→R, right T→B, bottom R→L,
  /// left B→T).  The `phase` parameter shifts the gradient start point
  /// around the perimeter. Changing `phase` inside `withAnimation { … }` drives the pipeline's
  /// animation controller to interpolate the phase smoothly frame by
  /// frame.
  public func border(
    blend: BorderBlend,
    set: BorderSet = .rounded,
    placement: StrokeStyle.Placement = .inset,
    sides: Edge.Set = .all,
    phase: Double = 0
  ) -> some View {
    borderModified(
      set: set,
      placement: placement,
      foreground: nil,
      background: nil,
      blend: blend,
      blendPhase: phase,
      sides: sides
    )
  }

  private func borderModified(
    set: BorderSet,
    placement: StrokeStyle.Placement,
    foreground: BorderEdgeStyle?,
    background: BorderBackgroundStyle?,
    blend: BorderBlend?,
    blendPhase: Double,
    sides: Edge.Set
  ) -> some View {
    modifier(
      BorderModifier(
        set: set,
        placement: placement,
        foreground: foreground,
        background: background,
        blend: blend,
        blendPhase: blendPhase,
        sides: sides
      )
    )
  }

  /// Underlines every descendant text run, matching SwiftUI's ambient
  /// propagation: an environment write that descendant `Text` stamps where
  /// its own value styling is unset. A directly-styled descendant,
  /// including an explicit `Text.underline(false)` clear, wins over the
  /// inherited style; `underline(false)` at the `View` level clears an
  /// inherited underline for the subtree.
  public func underline(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> some View {
    environment(\.underlineStyle, isActive ? .init(color: color) : nil)
  }

  /// Underlines every descendant text run with an explicit line pattern.
  ///
  /// Behaves like `underline(_:color:)` and adds the pattern: an ambient
  /// environment write that a descendant ``Text`` stamps where its own value
  /// styling is unset, and that a directly-styled descendant overrides.
  /// Passing `false` clears an inherited underline for the subtree.
  ///
  /// ```swift
  /// VStack { rows }
  ///   .underline(pattern: .dashed, color: .yellow)
  /// ```
  ///
  /// - Parameters:
  ///   - isActive: Whether to underline. Passing `false` clears the subtree's
  ///     inherited underline.
  ///   - pattern: The line pattern to draw.
  ///   - color: The underline color, or `nil` to use the run's foreground.
  public func underline(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    environment(\.underlineStyle, isActive ? .init(pattern: pattern, color: color) : nil)
  }

  /// Strikes through every descendant text run.
  ///
  /// An ambient environment write, matching `underline(_:color:)`: a
  /// descendant ``Text`` stamps it where its own value styling is unset, and a
  /// directly-styled descendant, including an explicit
  /// `Text.strikethrough(false)` clear, wins over the inherited style. Passing
  /// `false` at the ``View`` level clears an inherited strikethrough for the
  /// subtree.
  ///
  /// ```swift
  /// VStack { rows }
  ///   .strikethrough(isRemoved)
  /// ```
  ///
  /// - Parameters:
  ///   - isActive: Whether to strike through. Passing `false` clears the
  ///     subtree's inherited strikethrough.
  ///   - color: The line color, or `nil` to use the run's foreground.
  public func strikethrough(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> some View {
    environment(\.strikethroughStyle, isActive ? .init(color: color) : nil)
  }

  /// Strikes through every descendant text run with an explicit line pattern.
  ///
  /// Behaves like `strikethrough(_:color:)` and adds the pattern.
  ///
  /// ```swift
  /// VStack { rows }
  ///   .strikethrough(pattern: .double, color: .red)
  /// ```
  ///
  /// - Parameters:
  ///   - isActive: Whether to strike through. Passing `false` clears the
  ///     subtree's inherited strikethrough.
  ///   - pattern: The line pattern to draw.
  ///   - color: The line color, or `nil` to use the run's foreground.
  public func strikethrough(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    environment(\.strikethroughStyle, isActive ? .init(pattern: pattern, color: color) : nil)
  }

  /// Overrides the separator visibility for the list or table rows in this
  /// view.
  ///
  /// Attached to the row rather than the container: it travels with the row's
  /// draw metadata, so the nearest value on a given row wins over the value
  /// the ``ListStyle`` or ``TableStyle`` presentation supplies. Edges not
  /// named in `edges` keep the style's value.
  ///
  /// ```swift
  /// List(rows) { row in
  ///   RowView(row)
  ///     .listRowSeparator(.hidden, edges: .bottom)
  /// }
  /// ```
  ///
  /// - Parameters:
  ///   - visibility: The separator visibility for the named edges.
  ///   - edges: The row edges to override. Defaults to both.
  ///
  /// See <doc:Collections>.
  public func listRowSeparator(
    _ visibility: Visibility,
    edges: VerticalEdge.Set = .all
  ) -> some View {
    drawMetadata(
      .init(
        listStyle: .init(
          rowSeparatorTopVisibility: edges.contains(.top) ? visibility : nil,
          rowSeparatorBottomVisibility: edges.contains(.bottom) ? visibility : nil
        )
      )
    )
  }

  /// Overrides the background paint of the list or table row this view is in.
  ///
  /// Travels with the row's draw metadata, so it wins over the row surface the
  /// ``ListStyle`` or ``TableStyle`` presentation supplies. Selection and
  /// focus chrome still draw over it.
  ///
  /// ```swift
  /// List(rows) { row in
  ///   RowView(row)
  ///     .listRowBackground(SemanticShapeStyle.fill)
  /// }
  /// ```
  ///
  /// - Parameter style: The paint for the row's background cells.
  ///
  /// See <doc:Collections>.
  public func listRowBackground<S: ShapeStyle>(_ style: S) -> some View {
    drawMetadata(
      .init(listStyle: .init(rowBackgroundStyle: AnyShapeStyle(style)))
    )
  }

  /// Overrides the foreground paint of the list or table row this view is in.
  ///
  /// Travels with the row's draw metadata, so it wins over the row foreground
  /// the ``ListStyle`` or ``TableStyle`` presentation supplies, for that row
  /// only.
  ///
  /// ```swift
  /// List(rows) { row in
  ///   RowView(row)
  ///     .listRowForegroundStyle(SemanticShapeStyle.danger)
  /// }
  /// ```
  ///
  /// - Parameter style: The paint for the row's text and glyphs.
  ///
  /// See <doc:Collections>.
  public func listRowForegroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    drawMetadata(
      .init(listStyle: .init(rowForegroundStyle: AnyShapeStyle(style)))
    )
  }

  /// Overrides the separator visibility at the edges of the list section this
  /// view is in.
  ///
  /// The section counterpart of `listRowSeparator(_:edges:)`: it travels with
  /// draw metadata and wins over the ``ListStyle`` presentation for the named
  /// edges only.
  ///
  /// ```swift
  /// Section {
  ///   rows
  /// }
  /// .listSectionSeparator(.hidden, edges: .top)
  /// ```
  ///
  /// - Parameters:
  ///   - visibility: The separator visibility for the named edges.
  ///   - edges: The section edges to override. Defaults to both.
  ///
  /// See <doc:Collections>.
  public func listSectionSeparator(
    _ visibility: Visibility,
    edges: VerticalEdge.Set = .all
  ) -> some View {
    drawMetadata(
      .init(
        listStyle: .init(
          sectionSeparatorTopVisibility: edges.contains(.top) ? visibility : nil,
          sectionSeparatorBottomVisibility: edges.contains(.bottom) ? visibility : nil
        )
      )
    )
  }
}

extension ActionScope where Self: View {
  /// Sets the command palette style for this scope's subtree while preserving
  /// the `ActionScope` conformance, so a `paletteSheet(_:isPresented:)`
  /// declaration can follow.
  ///
  /// `environment(_:_:)` erases to `some View`, which would drop the
  /// conformance and with it the scope identity that absorbs
  /// `paletteCommand(...)` contributions. This applies the same environment
  /// write directly, and `ModifiedContent` conditionally conforms to
  /// `ActionScope`. The stored value is otherwise identical to the ``View``
  /// overload of `paletteStyle(_:)`: it reaches every palette below this
  /// modifier, and the nearest one wins.
  ///
  /// ```swift
  /// myScope
  ///   .paletteStyle(BadgePaletteStyle())
  ///   .paletteSheet("Commands", isPresented: $showsPalette)
  /// ```
  ///
  /// - Parameter style: The type-erased palette style to install.
  ///
  /// See <doc:Style-System> and <doc:Commands-And-Key-Input>.
  @MainActor
  public func paletteStyle(_ style: AnyPaletteStyle) -> some View & ActionScope {
    modifier(EnvironmentWritingModifier(keyPath: \.paletteStyle, value: style))
  }
  /// Sets the command palette style for this scope's subtree from a concrete
  /// style, preserving the `ActionScope` conformance.
  ///
  /// Equivalent to wrapping `style` in ``AnyPaletteStyle``.
  ///
  /// - Parameter style: A built-in style or a custom ``PaletteStyle``
  ///   conformer.
  ///
  /// See <doc:Style-System> and <doc:Commands-And-Key-Input>.
  @MainActor
  public func paletteStyle<S: PaletteStyle>(_ style: S) -> some View & ActionScope {
    paletteStyle(AnyPaletteStyle(style))
  }
}

/// The modifier `tag(_:includeOptional:)` applies.
///
/// Public so the tagged view's type can be written out; its stored
/// properties and behavior are internal to the framework. Apply it through
/// `tag(_:includeOptional:)` rather than constructing it.
public struct TagValueModifier<Value: Hashable & Sendable>: IterativePrimitiveViewModifier,
  Sendable,
  Equatable
{
  package var tag: Value
  package var includeOptional: Bool

  package func makeResolveWork<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> ResolveWork<[ResolvedNode]> {
    let tagged = SemanticMetadataModifier(
      metadata: .init(
        selectionTag: .init(
          value: tag,
          includeOptional: includeOptional
        )
      )
    )
    return tagged.makeResolveWork(content: content, in: context)
  }
}

extension TagValueModifier: TabItemMetadataProvidingModifier {
  package var tabItemMetadataContribution: PeekedTabChildMetadata {
    PeekedTabChildMetadata(
      label: nil,
      tag: SelectionTag(
        value: tag,
        includeOptional: includeOptional
      )
    )
  }
}

extension View {
  package func pickerViewportLineCount(
    _ count: Int?
  ) -> some View {
    environment(\.pickerViewportLineCount, count)
  }

  package func pickerLineWidth(
    _ width: Int?
  ) -> some View {
    environment(\.pickerLineWidth, width)
  }
}
