/// A continuous point in host or protocol pixel space.
///
/// Pixel coordinates are provenance for host input and diagnostics. Authored
/// pointer values use continuous terminal cell-space ``Point``.
public struct PixelPoint: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public static let zero = Self(x: 0, y: 0)
}

/// An integer extent in host or image pixel space.
///
/// `PixelSize` is distinct from ``CellSize`` because image grids and terminal
/// cells have different units even when both are represented by integers.
public struct PixelSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public static let zero = Self(width: 0, height: 0)
}
