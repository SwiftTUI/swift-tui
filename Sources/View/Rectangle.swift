public import Core

/// A rectangular shape.
public struct Rectangle: Shape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .rectangle
  }
}
