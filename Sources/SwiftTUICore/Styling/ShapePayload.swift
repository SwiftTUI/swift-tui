/// Fill mode used when rendering shapes.
public enum ShapeFillMode: Equatable, Sendable {
  case full
  case interior(strokeWidth: Int)
}

/// Supported low-level shape geometries.
public enum ShapeGeometry: Equatable, Sendable {
  case rectangle
  case roundedRectangle(cornerRadius: Int)
  case circle
  case ellipse
  case capsule
}

/// The draw operation applied to a shape geometry.
public enum ShapeOperation: Equatable, Sendable {
  case fill(
    style: AnyShapeStyle?,
    mode: ShapeFillMode = .full
  )
  case stroke(
    style: AnyShapeStyle?,
    strokeStyle: StrokeStyle,
    strokeBorder: Bool,
    backgroundStyle: BorderBackgroundStyle? = nil
  )
}

/// Low-level draw payload for a shape node.
public struct ShapePayload: Equatable, Sendable {
  public var geometry: ShapeGeometry
  public var insetAmount: Int
  public var operation: ShapeOperation

  public init(
    geometry: ShapeGeometry,
    insetAmount: Int = 0,
    operation: ShapeOperation
  ) {
    self.geometry = geometry
    self.insetAmount = max(0, insetAmount)
    self.operation = operation
  }
}
