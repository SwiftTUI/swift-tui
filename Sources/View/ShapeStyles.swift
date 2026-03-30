public import Core

/// A view that renders a geometric shape using fill or stroke operations.
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  var kindName: String { get }
}

extension Shape {
  public var kindName: String {
    String(describing: Self.self)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            operation: .fill(style: nil, mode: .full)
          )
        ),
        in: context
      )
    ]
  }

  public func fill<S: ShapeStyle>(_ style: S) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      operation: .fill(style: AnyShapeStyle(style), mode: .full)
    )
  }

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

  public func stroke<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: false,
        backgroundStyle: backgroundStyle
      )
    )
  }

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

  public func strokeBorder<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    background backgroundStyle: BorderBackgroundStyle?
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: true,
        backgroundStyle: backgroundStyle
      )
    )
  }

  package func chromeFill<S: ShapeStyle>(
    _ style: S,
    strokeWidth: Int = 1
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      operation: .fill(
        style: AnyShapeStyle(style),
        mode: .interior(strokeWidth: max(1, strokeWidth))
      )
    )
  }

  package func chromeStrokeBorder<S: ShapeStyle>(
    _ style: S,
    style strokeStyle: StrokeStyle = .init(),
    backgroundStyle: AnyShapeStyle? = nil
  ) -> some View {
    ShapeRenderView(
      kindName: kindName,
      geometry: geometry,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: true,
        backgroundStyle: backgroundStyle.map { .init(all: $0) }
      )
    )
  }
}

private struct ShapeRenderView: View, ResolvableView {
  var kindName: String
  var geometry: ShapeGeometry
  var operation: ShapeOperation

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            operation: operation
          )
        ),
        in: context
      )
    ]
  }
}
