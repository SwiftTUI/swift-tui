public import Core

/// A rectangle with rounded corners expressed in terminal cells.
public struct RoundedRectangle: Shape, ResolvableView {
  public var cornerRadius: Int

  public init(cornerRadius: Int) {
    self.cornerRadius = cornerRadius
  }

  public var geometry: ShapeGeometry {
    .roundedRectangle(cornerRadius: max(0, cornerRadius))
  }
}
