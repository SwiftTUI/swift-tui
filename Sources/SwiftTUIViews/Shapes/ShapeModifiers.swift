@_spi(Testing) public import SwiftTUICore

// MARK: - Fill

extension Shape {
  /// Fills the shape with an explicit shape style.
  public func fill<S: ShapeStyle>(_ style: S) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .fill(style: AnyShapeStyle(style), mode: .full)
    )
  }

  /// Fills the shape with the inherited foreground style.
  ///
  /// Mirrors SwiftUI's `fill(style:)`: with no explicit ``SwiftTUICore/ShapeStyle`` the
  /// shape resolves through the active `foregroundStyle` (and ultimately the
  /// semantic ``SwiftTUICore/SemanticStyleRole/foreground`` role).
  public func fill() -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .fill(style: nil, mode: .full)
    )
  }
}

// MARK: - Stroke

extension Shape {
  /// Strokes the shape's outline with an explicit shape style.
  public func stroke<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init()
  ) -> some View {
    stroke(
      style,
      style: strokeStyle,
      background: nil as BorderBackgroundStyle?
    )
  }

  /// Strokes the shape's outline with an explicit shape style and a border
  /// background.
  public func stroke<S: ShapeStyle, B: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: B
  ) -> some View {
    stroke(
      style,
      style: strokeStyle,
      background: BorderBackgroundStyle(backgroundStyle)
    )
  }

  /// Strokes the shape's outline with the inherited foreground style.
  public func stroke(
    style strokeStyle: StrokeStyle = .init()
  ) -> some View {
    stroke(
      style: strokeStyle,
      background: nil as BorderBackgroundStyle?
    )
  }

  /// Strokes the shape's outline with the inherited foreground style and a
  /// border background.
  public func stroke<B: ShapeStyle>(
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: B
  ) -> some View {
    stroke(
      style: strokeStyle,
      background: BorderBackgroundStyle(backgroundStyle)
    )
  }

  package func stroke<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: false,
        backgroundStyle: backgroundStyle
      )
    )
  }

  package func stroke(
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .stroke(
        style: nil,
        strokeStyle: strokeStyle,
        strokeBorder: false,
        backgroundStyle: backgroundStyle
      )
    )
  }
}

// MARK: - Stroke border

extension InsettableShape {
  /// Strokes a border inside the shape with an explicit shape style.
  public func strokeBorder<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init()
  ) -> some View {
    strokeBorder(
      style,
      style: strokeStyle,
      background: nil as BorderBackgroundStyle?
    )
  }

  /// Strokes a border inside the shape with an explicit shape style and a
  /// border background.
  public func strokeBorder<S: ShapeStyle, B: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: B
  ) -> some View {
    strokeBorder(
      style,
      style: strokeStyle,
      background: BorderBackgroundStyle(backgroundStyle)
    )
  }

  /// Strokes a border inside the shape with the inherited foreground style.
  ///
  /// Mirrors SwiftUI's `strokeBorder(style:antialiased:)`: with no explicit
  /// ``SwiftTUICore/ShapeStyle`` the border resolves through the active `foregroundStyle`
  /// (and ultimately the semantic ``SwiftTUICore/SemanticStyleRole/separator`` role).
  public func strokeBorder(
    style strokeStyle: StrokeStyle = .init()
  ) -> some View {
    strokeBorder(
      style: strokeStyle,
      background: nil as BorderBackgroundStyle?
    )
  }

  /// Strokes a border inside the shape with the inherited foreground style and
  /// a border background.
  public func strokeBorder<B: ShapeStyle>(
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: B
  ) -> some View {
    strokeBorder(
      style: strokeStyle,
      background: BorderBackgroundStyle(backgroundStyle)
    )
  }

  package func strokeBorder<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: true,
        backgroundStyle: backgroundStyle
      )
    )
  }

  package func strokeBorder(
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      insetAmount: insetAmount,
      operation: .stroke(
        style: nil,
        strokeStyle: strokeStyle,
        strokeBorder: true,
        backgroundStyle: backgroundStyle
      )
    )
  }
}
