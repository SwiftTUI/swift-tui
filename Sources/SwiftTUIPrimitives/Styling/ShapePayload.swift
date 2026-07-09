/// Fill mode used when rendering shapes.
public enum ShapeFillMode: Equatable, Sendable {
  case full
  case interior(strokeWidth: Int)
}

/// A copy-on-write container for a rendering ``Path`` carried by
/// ``ShapeGeometry/path(_:_:)``.
///
/// The box gives the geometry value O(1) equality on unchanged frames
/// (pointer identity short-circuits the structural compare), so custom-path
/// nodes do not regress the retained-reuse fast paths. The wrapped path is
/// module-internal plumbing — author-facing code uses `Shape.path(in:)`, not
/// this type directly.
public struct BoxedPath: Equatable, Sendable {
  private var storage: Boxed<Path>

  package init(_ path: Path) {
    storage = Boxed(path)
  }

  package var path: Path {
    storage.value
  }
}

/// Supported low-level shape geometries.
public enum ShapeGeometry: Equatable, Sendable {
  case rectangle
  case roundedRectangle(cornerRadius: Int)
  case circle
  case ellipse
  case capsule
  /// A free-form custom path in normalized unit-rect coordinates, filled
  /// under the given winding rule. Scaled into the placed frame at raster
  /// time. `indirect` keeps the five analytic cases a single enum word.
  indirect case path(BoxedPath, FillRule)
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
