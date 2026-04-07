public import Core

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
    _ style: ButtonStyle
  ) -> some View {
    environment(\.buttonStyle, style)
  }

  public func textFieldStyle(
    _ style: TextFieldStyle
  ) -> some View {
    environment(\.textFieldStyle, style)
  }

  public func pickerStyle(
    _ style: PickerStyle
  ) -> some View {
    environment(\.pickerStyle, style)
  }

  public func listStyle(
    _ style: ListStyle
  ) -> some View {
    environment(\.listStyle, style)
  }

  /// Control how tab views render their tab bar.
  public func tabViewStyle(
    _ style: TabViewStyle
  ) -> some View {
    environment(\.tabViewStyle, style)
  }

  public func toolbarStyle(
    _ style: ToolbarStyle
  ) -> some View {
    environment(\.toolbarStyle, style)
  }

  public func outlineStyle(
    _ style: OutlineStyle
  ) -> some View {
    environment(\.outlineStyle, style)
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
    EnvironmentWritingModifier(
      content: self,
      keyPath: \.foregroundStyle,
      value: AnyShapeStyle(style)
    )
  }

  public func tint<S: ShapeStyle>(_ style: S) -> some View {
    EnvironmentWritingModifier(
      content: self,
      keyPath: \.tintStyle,
      value: AnyShapeStyle(style)
    )
  }

  public func tint<S: ShapeStyle>(_ style: S?) -> some View {
    environment(\.tintStyle, style.map(AnyShapeStyle.init))
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
    TagValueView(
      content: self,
      tag: tag,
      includeOptional: includeOptional
    )
  }

  public func background<S: ShapeStyle>(_ style: S) -> some View {
    background {
      Rectangle().fill(style)
    }
  }

  public func border<S: ShapeStyle>(
    _ style: S,
    width: Int = 1
  ) -> some View {
    border(
      style,
      width: width,
      background: nil as BorderBackgroundStyle?
    )
  }

  public func border<S: ShapeStyle, B: ShapeStyle>(
    _ style: S,
    width: Int = 1,
    background backgroundStyle: B
  ) -> some View {
    border(
      style,
      width: width,
      background: BorderBackgroundStyle(backgroundStyle)
    )
  }

  public func border<S: ShapeStyle>(
    _ style: S,
    width: Int = 1,
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    overlay {
      Rectangle().strokeBorder(
        style,
        style: .init(lineWidth: width),
        background: backgroundStyle
      )
    }
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

public struct TagValueView<Content: View, Value: Hashable & Sendable>: View, ResolvableView {
  var content: Content
  var tag: Value
  var includeOptional: Bool

  public init(
    content: Content,
    tag: Value,
    includeOptional: Bool = true
  ) {
    self.content = content
    self.tag = tag
    self.includeOptional = includeOptional
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let tagged = SemanticMetadataModifier(
      content: content,
      metadata: .init(
        selectionTag: .init(
          value: tag,
          includeOptional: includeOptional
        )
      )
    )
    return tagged.resolveElements(in: context)
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
