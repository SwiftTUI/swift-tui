@_spi(Testing) import SwiftTUICore

/// The view that carries a shape's resolved geometry and draw operation
/// (fill or stroke) into the resolve pipeline. Shared by every shape
/// modifier in ``ShapeModifiers``.
struct ShapeRenderView: PrimitiveView, ResolvableView {
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
