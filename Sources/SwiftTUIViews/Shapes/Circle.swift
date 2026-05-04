public import SwiftTUICore

/// A circular shape inscribed in its frame's shortest axis.
///
/// Aspect-corrected using ``/SwiftTUICore/CellPixelMetrics`` from the resolve
/// environment so the emitted shape is pixel-true regardless of the
/// terminal's cell aspect ratio.
public struct Circle: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .circle
  }
}
