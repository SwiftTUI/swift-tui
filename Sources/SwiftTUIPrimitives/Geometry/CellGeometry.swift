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

/// An integer coordinate in a canvas's grid-sample space.
///
/// A ``Canvas`` is sized in terminal cells, but its ``CanvasGrid`` subdivides
/// each cell into a fixed number of drawing samples (for example, 2×4 for
/// Braille). `GridSample` addresses one of those sub-cell samples directly.
///
/// `GridSample` is intentionally distinct from ``CellPoint``: both carry an
/// integer `x`/`y`, but they live in different coordinate spaces. A
/// `GridSample` of `(1, 1)` is a single Braille dot, while a ``CellPoint`` of
/// `(1, 1)` is a whole terminal cell (a 2×4 block of samples). Keeping them as
/// separate types lets the compiler catch coordinate-space mix-ups that loose
/// integers would silently allow. Map a continuous ``Point`` to the sample
/// containing it with ``CanvasContext/gridSample(for:)-(Point)``.
public struct GridSample: Equatable, Hashable, Sendable {
  public var x: Int
  public var y: Int

  public init(x: Int, y: Int) {
    self.x = x
    self.y = y
  }

  public static let zero = Self(x: 0, y: 0)
}

/// An integer size in canvas grid samples.
///
/// The sample-space extent of a ``CanvasContext`` drawing surface — the cell
/// ``CellSize`` multiplied by the active ``CanvasGrid``'s subdivisions. Read it
/// from ``CanvasContext/gridSize``.
public struct GridSize: Equatable, Hashable, Sendable {
  public var width: Int
  public var height: Int

  public init(width: Int, height: Int) {
    self.width = width
    self.height = height
  }

  public static let zero = Self(width: 0, height: 0)
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

  /// The bounding box enclosing `self` and `other`, treating an empty rect as no
  /// contribution (so `zero.union(r) == r`). Used internally to aggregate a
  /// subtree's absolute paint extent; `package` so it stays off the public API
  /// surface.
  package func union(_ other: CellRect) -> CellRect {
    if isEmpty {
      return other
    }
    if other.isEmpty {
      return self
    }
    let minX = min(origin.x, other.origin.x)
    let minY = min(origin.y, other.origin.y)
    let maxX = max(self.maxX, other.maxX)
    let maxY = max(self.maxY, other.maxY)
    return CellRect(
      origin: .init(x: minX, y: minY),
      size: .init(width: maxX - minX, height: maxY - minY)
    )
  }
}
