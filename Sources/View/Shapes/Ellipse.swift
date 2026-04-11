public import Core

/// An ellipse inscribed in its frame.
public struct Ellipse: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .ellipse
  }
}
