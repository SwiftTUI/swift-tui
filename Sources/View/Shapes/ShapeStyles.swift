public import Core
@_spi(Testing) import Core

/// A view that renders a geometric shape using fill or stroke operations.
public protocol Shape: View {
  var geometry: ShapeGeometry { get }
  var kindName: String { get }
  var insetAmount: Int { get }
}

/// A shape that can be inset geometrically before being rendered.
public protocol InsettableShape: Shape {}

/// A shape wrapper that insets its base geometry before rendering.
public struct InsetShape<Base: InsettableShape>: InsettableShape, ResolvableView {
  public var base: Base
  public var amount: Int

  public init(
    base: Base,
    amount: Int
  ) {
    self.base = base
    self.amount = amount
  }

  public var geometry: ShapeGeometry {
    base.geometry
  }

  public var kindName: String {
    base.kindName
  }

  public var insetAmount: Int {
    base.insetAmount + max(0, amount)
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            insetAmount: insetAmount,
            operation: .fill(style: nil, mode: .full)
          )
        ),
        in: context
      )
    ]
  }
}

extension Shape {
  public var kindName: String {
    String(describing: Self.self)
  }

  public var insetAmount: Int {
    0
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            insetAmount: insetAmount,
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
      insetAmount: insetAmount,
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
      insetAmount: insetAmount,
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
      insetAmount: insetAmount,
      operation: .stroke(
        style: AnyShapeStyle(style),
        strokeStyle: strokeStyle,
        strokeBorder: true,
        backgroundStyle: backgroundStyle
      )
    )
  }

}

extension InsettableShape {
  public func inset(by amount: Int) -> some InsettableShape {
    InsetShape(
      base: self,
      amount: max(0, amount)
    )
  }
}

private struct ShapeRenderView: View, ResolvableView {
  var kindName: String
  var geometry: ShapeGeometry
  var insetAmount: Int
  var operation: ShapeOperation

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(
          .init(
            geometry: geometry,
            insetAmount: insetAmount,
            operation: operation
          )
        ),
        in: context
      )
    ]
  }
}
