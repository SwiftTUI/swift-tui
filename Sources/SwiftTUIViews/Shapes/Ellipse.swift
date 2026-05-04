public import SwiftTUICore

/// An ellipse inscribed in its frame.
///
/// Aspect-corrected using ``/SwiftTUICore/CellPixelMetrics`` from the resolve
/// environment so the emitted shape is pixel-true regardless of the
/// terminal's cell aspect ratio.
public struct Ellipse: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .ellipse
  }
}
