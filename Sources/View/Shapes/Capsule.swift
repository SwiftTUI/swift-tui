public import Core

/// A capsule (rectangle with semicircular short-axis ends) inscribed
/// in its frame.
public struct Capsule: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .capsule
  }
}
