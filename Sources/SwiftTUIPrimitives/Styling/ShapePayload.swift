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
  package func path(
    in rect: Rect, stretchingCircle: Bool = false, trimAspectRatio: Double = 1
  ) -> Path {
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
      return base.path(
        in: rect, stretchingCircle: stretchingCircle, trimAspectRatio: trimAspectRatio
      )
      .physicallyTrimmedPath(from: from, to: to, aspectRatio: trimAspectRatio)
    }
  }

  /// Lower a placed trim to normalized path geometry once per paint. Keeping
  /// the recipe until this point avoids baking a one-cell corner radius into
  /// a unit square and then stretching that radius with the frame.
  package func resolved(in size: CellSize, trimAspectRatio: Double = 1) -> ShapeGeometry {
    guard case .trimmed = self, size.width > 0, size.height > 0 else { return self }
    let width = Double(size.width)
    let height = Double(size.height)
    let placed = path(
      in: Rect(origin: .zero, size: Size(width: width, height: height)),
      stretchingCircle: true, trimAspectRatio: trimAspectRatio)
    return .path(BoxedPath(placed.scaledBy(sx: 1 / width, sy: 1 / height)), fillRule)
  }
}

extension Path {
  /// Trims a cell-space outline by fractions of its physical length: a
  /// vertical cell counts `aspectRatio` cell widths. The raster's placed trims
  /// and the public `TrimmedShape.path(in:)` share this measure, so a path
  /// built from a trimmed shape describes the outline its fill paints.
  ///
  /// Scaling y by the aspect ratio can take a far, finite point past the
  /// `Double` range, and the trim of a non-finite outline is empty. Such an
  /// outline is first scaled down by a power of two that keeps it finite. A
  /// power-of-two scale changes only exponents, so with the flattening
  /// tolerance scaled alike the trim cuts the scaled outline at the scaled
  /// points, which scale back exactly. Every other outline takes the plain
  /// scale, bit for bit.
  package func physicallyTrimmedPath(from: Double, to: Double, aspectRatio: Double) -> Path {
    let shrink =
      overflowsVerticalScale(aspectRatio)
      ? Double(sign: .plus, exponent: -(aspectRatio.exponent + 1), significand: 1) : 1
    return scaledBy(sx: shrink, sy: shrink * aspectRatio)
      .trimmedPath(from: from, to: to, tolerance: 0.01 * shrink)
      .scaledBy(sx: 1 / shrink, sy: 1 / (shrink * aspectRatio))
  }

  /// Whether a finite y coordinate of this path leaves the `Double` range
  /// when multiplied by `scale`.
  private func overflowsVerticalScale(_ scale: Double) -> Bool {
    guard scale.isFinite, scale > 1 else { return false }
    func overflows(_ point: Point) -> Bool {
      point.y.isFinite && !(point.y * scale).isFinite
    }
    return elements.contains { element in
      switch element {
      case .move(let point), .line(let point): overflows(point)
      case .quadCurve(let to, let control): overflows(to) || overflows(control)
      case .curve(let to, let control1, let control2):
        overflows(to) || overflows(control1) || overflows(control2)
      case .close: false
      }
    }
  }
}
