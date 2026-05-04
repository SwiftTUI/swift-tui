/// An integer point in the terminal cell grid.
///
/// `CellPoint` is used by layout, rasterization, semantic hit regions, and
/// terminal output. Pointer input projects to this grid for routing but carries
/// a continuous ``Point`` for authored consumers.
public struct CellPoint: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public static let zero = Self(x: 0, y: 0)
}

/// An integer size in terminal cells.
public struct CellSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public static let zero = Self(width: 0, height: 0)
}

/// An integer rectangle in terminal cells.
///
/// Cell rectangles are half-open: `[origin.x, maxX) x [origin.y, maxY)`.
public struct CellRect: Equatable, Hashable, Sendable {
  public var origin: CellPoint
  public var size: CellSize

  public init(origin: CellPoint, size: CellSize) {
    self.origin = origin
    self.size = size
  }

  public static let zero = Self(origin: .zero, size: .zero)

  public var isEmpty: Bool {
    size.width <= 0 || size.height <= 0
  }

  public var maxX: Int {
    origin.x + size.width
  }

  public var maxY: Int {
    origin.y + size.height
  }

  public func contains(_ cell: CellPoint) -> Bool {
    guard !isEmpty else {
      return false
    }

    return cell.x >= origin.x
      && cell.x < maxX
      && cell.y >= origin.y
      && cell.y < maxY
  }

  public func contains(_ point: Point) -> Bool {
    guard !isEmpty else {
      return false
    }

    return point.x >= Double(origin.x)
      && point.x < Double(maxX)
      && point.y >= Double(origin.y)
      && point.y < Double(maxY)
  }

  public var continuous: Rect {
    Rect(
      origin: Point(self.origin),
      size: Size(width: Double(size.width), height: Double(size.height))
    )
  }

  public func intersection(_ other: CellRect) -> CellRect? {
    let minX = max(origin.x, other.origin.x)
    let minY = max(origin.y, other.origin.y)
    let maxX = min(self.maxX, other.maxX)
    let maxY = min(self.maxY, other.maxY)

    guard maxX > minX, maxY > minY else {
      return nil
    }

    return CellRect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }
}
