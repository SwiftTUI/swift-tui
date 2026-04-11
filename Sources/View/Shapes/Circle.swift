public import Core

/// A circular shape inscribed in its frame's shortest axis.
public struct Circle: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .circle
  }
}
