/// Fill mode used when rendering shapes.
public enum ShapeFillMode: Equatable, Sendable {
  case full
  case interior(strokeWidth: Int)
}

/// A copy-on-write container for a rendering ``Path`` carried by
/// ``ShapeGeometry/path(_:_:)``.
///
/// The box gives the geometry value O(1) equality on unchanged frames.
/// Pointer identity stops the structural comparison early.
/// Thus, custom-path nodes do not slow the retained-reuse fast paths. The wrapped path is
/// module-internal plumbing; author-facing code uses `Shape.path(in:)`, not
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
  /// A fill/clip outline whose trim must be evaluated after placement, so
  /// absolute corner radii and the source winding rule survive composition.
  indirect case trimmed(ShapeGeometry, from: Double, to: Double)
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
    self.insetAmount = insetAmount
    self.operation = operation
  }
}

extension ShapeGeometry {
  package var fillRule: FillRule {
    switch self {
    case .path(_, let rule): return rule
    case .trimmed(let base, _, _): return base.fillRule
    default: return .nonZero
    }
  }

  /// Shared outline construction for the public path API and placed trims.
  /// Trimmed fills retain their documented frame-stretching circle policy.
  package func path(in rect: Rect, stretchingCircle: Bool = false) -> Path {
    switch self {
    case .rectangle:
      return Path(rect)
    case .roundedRectangle(let radius):
      return Path(roundedRect: rect, cornerRadius: Double(radius))
    case .circle where !stretchingCircle:
      let diameter = min(rect.size.width, rect.size.height)
      return Path(
        ellipseIn: Rect(
          origin: Point(
            x: rect.origin.x + (rect.size.width - diameter) / 2,
            y: rect.origin.y + (rect.size.height - diameter) / 2),
          size: Size(width: diameter, height: diameter)))
    case .circle, .ellipse:
      return Path(ellipseIn: rect)
    case .capsule:
      return Path(roundedRect: rect, cornerRadius: min(rect.size.width, rect.size.height) / 2)
    case .path(let boxed, _):
      return boxed.path.scaledBy(sx: rect.size.width, sy: rect.size.height)
        .translatedBy(dx: rect.origin.x, dy: rect.origin.y)
    case .trimmed(let base, let from, let to):
      return base.path(in: rect, stretchingCircle: stretchingCircle)
        .trimmedPath(from: from, to: to)
    }
  }

  /// Lower a placed trim to normalized path geometry once per paint. Keeping
  /// the recipe until this point avoids baking a one-cell corner radius into
  /// a unit square and then stretching that radius with the frame.
  package func resolved(in size: CellSize) -> ShapeGeometry {
    guard case .trimmed = self, size.width > 0, size.height > 0 else { return self }
    let width = Double(size.width)
    let height = Double(size.height)
    let placed = path(
      in: Rect(origin: .zero, size: Size(width: width, height: height)),
      stretchingCircle: true)
    return .path(BoxedPath(placed.scaledBy(sx: 1 / width, sy: 1 / height)), fillRule)
  }
}
