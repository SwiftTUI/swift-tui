@_spi(Testing) import SwiftTUICore

/// The view that carries a shape's resolved geometry and draw operation
/// (fill or stroke) into the resolve pipeline. Shared by every shape
/// modifier in ``ShapeModifiers``.
struct ShapeRenderView: PrimitiveView, ResolvableView {
  var kindName: ViewKind
  var geometry: ShapeGeometry
  var insetAmount: Int
  var operation: ShapeOperation
  /// The shape's data and the way back to geometry, when the shape conforms
  /// to `Animatable` (`Shape.animatableShapeProvider(fills:)`).
  var animatableShape: AnimatableShapeProvider?

  func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    var payload = ShapePayload(
      geometry: geometry,
      insetAmount: insetAmount,
      operation: operation
    )
    payload.animatableShape = animatableShape
    return [
      resolveLeafNode(
        kindName: kindName,
        drawPayload: .shape(payload),
        in: context
      )
    ]
  }
}
