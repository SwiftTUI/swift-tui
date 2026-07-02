public import SwiftTUICore

extension View {
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
    _ visibility: ScrollIndicatorVisibility
  ) -> some View {
    environment(\.scrollIndicatorVisibility, visibility)
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
  /// The default chrome is ``BorderSet/rounded`` in
  /// ``StrokeStyle/Placement/outset`` placement — the wrapped view's
  /// frame grows by the border set's per-side display widths so that
  /// content is never occluded.
  ///
  /// Pass `placement: .inset` to draw the border into the outermost
  /// cells of the content frame instead of reserving extra space; use
  /// this with inset-style border sets like ``BorderSet/innerHalfBlock``.
  ///
  /// For other glyph palettes (single-line, half-block, double-line,
  /// heavy, etc.) pass an explicit `set:`. See ``BorderSet`` for the
  /// full catalog.
  public func border<S: ShapeStyle>(
    _ style: S = SemanticShapeStyle.foreground,
    set: BorderSet = .rounded,
    placement: StrokeStyle.Placement = .outset,
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
    placement: StrokeStyle.Placement = .outset,
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
  /// around the perimeter from a ``BorderBlend``.
  ///
  /// The blend's stops are interpolated as the rasterizer walks the
  /// rectangle's edges clockwise (top L→R, right T→B, bottom R→L,
  /// left B→T).  The `phase` parameter shifts the gradient start point
  /// around the perimeter, enabling chasing-light animation: changing
  /// `phase` inside `withAnimation { … }` drives the pipeline's
  /// animation controller to interpolate the phase smoothly frame by
  /// frame.
  public func border(
    blend: BorderBlend,
    set: BorderSet = .rounded,
    placement: StrokeStyle.Placement = .outset,
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

  public func underline(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> some View {
    drawMetadata(
      .init(
        underlineStyle: isActive ? .init(color: color) : nil
      )
    )
  }

  public func underline(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    drawMetadata(
      .init(
        underlineStyle: isActive ? .init(pattern: pattern, color: color) : nil
      )
    )
  }

  public func strikethrough(
    _ isActive: Bool = true,
    color: Color? = nil
  ) -> some View {
    drawMetadata(
      .init(
        strikethroughStyle: isActive ? .init(color: color) : nil
      )
    )
  }

  public func strikethrough(
    _ isActive: Bool = true,
    pattern: Text.LineStyle.Pattern,
    color: Color? = nil
  ) -> some View {
    drawMetadata(
      .init(
        strikethroughStyle: isActive ? .init(pattern: pattern, color: color) : nil
      )
    )
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
