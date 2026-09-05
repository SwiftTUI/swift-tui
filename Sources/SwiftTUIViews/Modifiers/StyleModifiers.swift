public import SwiftTUICore

extension View {
  /// Sets the Slider composition for this subtree.
  public func sliderStyle(_ style: AnySliderStyle) -> some View {
    environment(\.sliderStyle, style)
  }
  public func sliderStyle<S: SliderStyle>(_ style: S) -> some View {
    sliderStyle(AnySliderStyle(style))
  }

  /// Sets the Stepper composition for this subtree.
  public func stepperStyle(_ style: AnyStepperStyle) -> some View {
    environment(\.stepperStyle, style)
  }
  public func stepperStyle<S: StepperStyle>(_ style: S) -> some View {
    stepperStyle(AnyStepperStyle(style))
  }

  /// Sets the Toggle composition for this subtree.
  public func toggleStyle(_ style: AnyToggleStyle) -> some View {
    environment(\.toggleStyle, style)
  }

  public func toggleStyle<S: ToggleStyle>(_ style: S) -> some View {
    toggleStyle(AnyToggleStyle(style))
  }


  /// Sets the DisclosureGroup composition for this subtree.
  public func disclosureGroupStyle(_ style: AnyDisclosureGroupStyle) -> some View {
    environment(\.disclosureGroupStyle, style)
  }

  public func disclosureGroupStyle<S: DisclosureGroupStyle>(_ style: S) -> some View {
    disclosureGroupStyle(AnyDisclosureGroupStyle(style))
  }


  /// Sets the TextEditor composition for this subtree.
  public func textEditorStyle(_ style: AnyTextEditorStyle) -> some View {
    environment(\.textEditorStyle, style)
  }

  public func textEditorStyle<S: TextEditorStyle>(_ style: S) -> some View {
    textEditorStyle(AnyTextEditorStyle(style))
  }


  /// Sets the ProgressView composition for this subtree.
  public func progressViewStyle(_ style: AnyProgressViewStyle) -> some View {
    environment(\.progressViewStyle, style)
  }

  public func progressViewStyle<S: ProgressViewStyle>(_ style: S) -> some View {
    progressViewStyle(AnyProgressViewStyle(style))
  }


  /// Sets the composition of labels in this subtree.
  public func labelStyle(_ style: AnyLabelStyle) -> some View {
    environment(\.labelStyle, style)
  }

  public func labelStyle<S: LabelStyle>(_ style: S) -> some View {
    labelStyle(AnyLabelStyle(style))
  }

  /// Sets the label and value layout of labeled content in this subtree.
  public func labeledContentStyle(_ style: AnyLabeledContentStyle) -> some View {
    environment(\.labeledContentStyle, style)
  }

  public func labeledContentStyle<S: LabeledContentStyle>(_ style: S) -> some View {
    labeledContentStyle(AnyLabeledContentStyle(style))
  }

  /// Sets the chrome and composition of group boxes in this subtree.
  public func groupBoxStyle(_ style: AnyGroupBoxStyle) -> some View {
    environment(\.groupBoxStyle, style)
  }

  public func groupBoxStyle<S: GroupBoxStyle>(_ style: S) -> some View {
    groupBoxStyle(AnyGroupBoxStyle(style))
  }

  public func controlProminence(
    _ prominence: ControlProminence
  ) -> some View {
    environment(\.controlProminence, prominence)
  }

  public func buttonBorderShape(
    _ shape: ButtonBorderShape
  ) -> some View {
    environment(\.buttonBorderShape, shape)
  }

  public func buttonStyle(
    _ style: AnyButtonStyle
  ) -> some View {
    environment(\.buttonStyle, style)
  }

  public func buttonStyle<S: ButtonStyle>(
    _ style: S
  ) -> some View {
    buttonStyle(AnyButtonStyle(style))
  }

  public func textFieldStyle(
    _ style: AnyTextFieldStyle
  ) -> some View {
    environment(\.textFieldStyle, style)
  }

  public func textFieldStyle<S: TextFieldStyle>(
    _ style: S
  ) -> some View {
    textFieldStyle(AnyTextFieldStyle(style))
  }

  public func pickerStyle(
    _ style: AnyPickerStyle
  ) -> some View {
    environment(\.pickerStyle, style)
  }

  public func pickerStyle<S: PickerStyle>(
    _ style: S
  ) -> some View {
    pickerStyle(AnyPickerStyle(style))
  }

  public func listStyle(
    _ style: AnyListStyle
  ) -> some View {
    environment(\.listStyle, style)
  }

  public func listStyle<S: ListStyle>(
    _ style: S
  ) -> some View {
    listStyle(AnyListStyle(style))
  }

  public func tableStyle(
    _ style: AnyTableStyle
  ) -> some View {
    environment(\.tableStyle, style)
  }

  public func tableStyle<S: TableStyle>(
    _ style: S
  ) -> some View {
    tableStyle(AnyTableStyle(style))
  }

  public func spinnerStyle(
    _ style: AnySpinnerStyle
  ) -> some View {
    environment(\.spinnerStyle, style)
  }

  public func spinnerStyle<S: SpinnerStyle>(
    _ style: S
  ) -> some View {
    spinnerStyle(AnySpinnerStyle(style))
  }

  /// Sets the sheet chrome for this view's subtree. A sheet declaration
  /// reads the nearest value when it presents.
  public func sheetStyle(
    _ style: AnySheetStyle
  ) -> some View {
    environment(\.sheetStyle, style)
  }

  public func sheetStyle<S: SheetStyle>(
    _ style: S
  ) -> some View {
    sheetStyle(AnySheetStyle(style))
  }

  /// Sets the toolbar style for this view's subtree. A toolbar host reads
  /// the nearest value, so this may sit on the host or on any ancestor.
  public func toolbarStyle(
    _ style: AnyToolbarStyle
  ) -> some View {
    environment(\.toolbarStyle, style)
  }

  public func toolbarStyle<S: ToolbarStyle>(
    _ style: S
  ) -> some View {
    toolbarStyle(AnyToolbarStyle(style))
  }

  /// Control how tab views render their tab bar.
  public func tabViewStyle(
    _ style: AnyTabViewStyle
  ) -> some View {
    environment(\.tabViewStyle, style)
  }

  public func tabViewStyle<S: TabViewStyle>(
    _ style: S
  ) -> some View {
    tabViewStyle(AnyTabViewStyle(style))
  }

  public func outlineStyle(
    _ style: AnyOutlineStyle
  ) -> some View {
    environment(\.outlineStyle, style)
  }

  public func outlineStyle<S: OutlineStyle>(
    _ style: S
  ) -> some View {
    outlineStyle(AnyOutlineStyle(style))
  }

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

  public func tableHeaders(
    _ visibility: TableHeaderVisibility
  ) -> some View {
    environment(\.tableHeaderVisibility, visibility)
  }

  public func openLinkAction(
    _ action: OpenLinkAction
  ) -> some View {
    environment(\.openLinkAction, action)
  }

  public func foregroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    modifier(
      EnvironmentWritingModifier(
        keyPath: \.foregroundStyle,
        value: AnyShapeStyle(style)
      )
    )
  }

  public func tint<S: ShapeStyle>(_ style: S) -> some View {
    modifier(
      EnvironmentWritingModifier(
        keyPath: \.tintStyle,
        value: AnyShapeStyle(style)
      )
    )
  }

  public func tint<S: ShapeStyle>(_ style: S?) -> some View {
    environment(\.tintStyle, style.map(AnyShapeStyle.init))
  }

  public func blendMode(_ blendMode: BlendMode) -> some View {
    modifier(DrawEffectModifier(effect: .blendMode(blendMode)))
  }

  public func compositingGroup() -> some View {
    modifier(DrawEffectModifier(effect: .compositingGroup))
  }

  public func disabled(_ isDisabled: Bool) -> some View {
    transformEnvironment(\.isEnabled) { isEnabled in
      isEnabled = isEnabled && !isDisabled
    }
  }

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

  public func underline(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    environment(\.underlineStyle, isActive ? .init(pattern: pattern, color: color) : nil)
  }

  public func strikethrough(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> some View {
    environment(\.strikethroughStyle, isActive ? .init(color: color) : nil)
  }

  public func strikethrough(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    environment(\.strikethroughStyle, isActive ? .init(pattern: pattern, color: color) : nil)
  }

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

  public func listRowBackground<S: ShapeStyle>(_ style: S) -> some View {
    drawMetadata(
      .init(listStyle: .init(rowBackgroundStyle: AnyShapeStyle(style)))
    )
  }

  public func listRowForegroundStyle<S: ShapeStyle>(_ style: S) -> some View {
    drawMetadata(
      .init(listStyle: .init(rowForegroundStyle: AnyShapeStyle(style)))
    )
  }

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

public struct TagValueModifier<Value: Hashable & Sendable>: PrimitiveViewModifier, Sendable,
  Equatable
{
  package var tag: Value
  package var includeOptional: Bool

  package func resolve<Content: View>(
    content: ModifierContentInputs<Content>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let tagged = SemanticMetadataModifier(
      metadata: .init(
        selectionTag: .init(
          value: tag,
          includeOptional: includeOptional
        )
      )
    )
    return tagged.resolve(content: content, in: context)
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
