public import SwiftTUICore

/// A rectangular shape.
public struct Rectangle: InsettableShape, ResolvableView {
  public init() {}

  public var geometry: ShapeGeometry {
    .rectangle
  }
}
