public import Core

/// A rectangular shape.
public struct Rectangle: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .rectangle
  }
}
