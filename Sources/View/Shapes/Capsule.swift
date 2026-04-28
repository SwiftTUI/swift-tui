public import Core

/// A capsule (rectangle with semicircular short-axis ends) inscribed
/// in its frame.
///
/// Aspect-corrected using ``/Core/CellPixelMetrics`` from the resolve
/// environment so the emitted shape is pixel-true regardless of the
/// terminal's cell aspect ratio.
public struct Capsule: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .capsule
  }
}
