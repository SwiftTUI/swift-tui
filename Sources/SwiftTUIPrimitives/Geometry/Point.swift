/// A continuous point in terminal cell space.
///
/// `Point` is the authored coordinate used by pointer input, gestures,
/// drawing, and interpolation. Layout and raster placement use ``CellPoint``.
public struct Point: Equatable, Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }

  public static let zero = Self(x: 0, y: 0)
}

extension Point {
  /// Creates the top-leading continuous point for an integer terminal cell.
  public init(_ cell: CellPoint) {
    self.init(x: Double(cell.x), y: Double(cell.y))
  }

  /// The integer cell containing this continuous point.
  ///
  /// Each coordinate is rounded down. A cell beyond `±(Int.max / 2)`
  /// saturates at that bound, and a NaN coordinate maps to `Int.min / 2`, a
  /// cell outside every finite region. The conversion never traps.
  public var containingCell: CellPoint {
    CellPoint(
      x: SaturatingConversion.int(x, rounding: .down),
      y: SaturatingConversion.int(y, rounding: .down)
    )
  }

  /// The normalized in-cell fraction for this point: each finite
  /// coordinate's offset from the integer at or below it, in `0..<1`.
  ///
  /// A coordinate so little below an integer that its exact offset rounds up
  /// to 1 (for example `-1e-17`) reports the largest fraction below 1
  /// instead, so the fraction stays within ``containingCell``.
  public var fractionInCell: UnitPoint {
    func fraction(_ value: Double) -> Double {
      let offset = value - value.rounded(.down)
      return offset == 1 ? Double(1).nextDown : offset
    }
    return UnitPoint(x: fraction(x), y: fraction(y))
  }

  /// Snaps this point to an integer cell using `rule`.
  ///
  /// Saturates and treats NaN as ``containingCell`` does.
  public func snapped(_ rule: FloatingPointRoundingRule) -> CellPoint {
    CellPoint(
      x: SaturatingConversion.int(x, rounding: rule),
      y: SaturatingConversion.int(y, rounding: rule)
    )
  }
}

/// A continuous size in terminal cell space.
///
/// `Size` is used by authored drawing/input geometry. Integer terminal layout
/// and raster extents use ``CellSize``.
public struct Size: Equatable, Hashable, Sendable {
  public var width: Double
  public var height: Double

  public init(width: Double, height: Double) {
    self.width = width
    self.height = height
  }

  public static let zero = Self(width: 0, height: 0)
}

/// A continuous vector in terminal cell space.
///
/// Gesture translations and velocities use vectors so they are not confused
/// with integer cell extents.
public struct Vector: Equatable, Hashable, Sendable {
  public var dx: Double
  public var dy: Double

  public init(dx: Double, dy: Double) {
    self.dx = dx
    self.dy = dy
  }

  public static let zero = Self(dx: 0, dy: 0)
}

/// A continuous rectangle in terminal cell space.
///
/// `Rect` is for authored drawing/input geometry. Layout frames, semantic
/// regions, and raster bounds use ``CellRect``.
public struct Rect: Equatable, Hashable, Sendable {
  public var origin: Point
  public var size: Size

  public init(origin: Point, size: Size) {
    self.origin = origin
    self.size = size
  }

  public static let zero = Self(origin: .zero, size: .zero)

  public var isEmpty: Bool {
    size.width <= 0 || size.height <= 0
  }

  public var maxX: Double {
    origin.x + size.width
  }

  public var maxY: Double {
    origin.y + size.height
  }

  public func contains(_ point: Point) -> Bool {
    guard !isEmpty else {
      return false
    }

    return point.x >= origin.x
      && point.x < maxX
      && point.y >= origin.y
      && point.y < maxY
  }

  public func intersection(_ other: Rect) -> Rect? {
    let minX = max(origin.x, other.origin.x)
    let minY = max(origin.y, other.origin.y)
    let maxX = min(self.maxX, other.maxX)
    let maxY = min(self.maxY, other.maxY)

    guard maxX > minX, maxY > minY else {
      return nil
    }

    return Rect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }
}
