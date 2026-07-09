/// Identifies the source of sub-cell pointer coordinates.
public enum PointerPrecisionSource: Equatable, Hashable, Sendable {
  /// Pixel coordinates reported by a terminal pointer protocol.
  case terminalPixels
  /// Pixel or logical-pixel coordinates reported by a native host.
  case nativePixels
  /// Pixel coordinates reported by the browser/web host.
  case webPixels
}

/// Describes how much precision a pointer event carries.
public enum PointerPrecision: Equatable, Hashable, Sendable {
  /// The event came from an integer terminal cell.
  case cell
  /// The event carries a fractional cell-space location derived from pixels.
  case subCell(source: PointerPrecisionSource, metrics: CellPixelMetrics)

  /// Whether this precision carries meaningful in-cell position.
  public var isSubCell: Bool {
    switch self {
    case .cell:
      return false
    case .subCell:
      return true
    }
  }
}

/// Pointer location normalized into terminal cell space.
///
/// `location` is the continuous cell-space point used by gestures and direct
/// manipulation. `cell` is the containing terminal cell used for routing and
/// legacy hit testing. `precision` records whether the point came from a
/// cell-only fallback or a sub-cell host/protocol path.
public struct PointerLocation: Equatable, Hashable, Sendable {
  public var location: Point
  public var cell: CellPoint
  public var precision: PointerPrecision
  public var rawPixel: PixelPoint?

  private init(
    location: Point,
    cell: CellPoint,
    precision: PointerPrecision,
    rawPixel: PixelPoint? = nil
  ) {
    self.location = location
    self.cell = cell
    self.precision = precision
    self.rawPixel = rawPixel
  }
}

extension PointerLocation {
  /// Builds a cell-only fallback using the center of `cell`.
  public static func cellFallback(
    _ cell: CellPoint
  ) -> PointerLocation {
    PointerLocation(
      location: Point(
        x: Double(cell.x) + 0.5,
        y: Double(cell.y) + 0.5
      ),
      cell: cell,
      precision: .cell,
      rawPixel: nil
    )
  }

  /// Builds a sub-cell pointer location from continuous cell coordinates.
  public static func subCell(
    location: Point,
    source: PointerPrecisionSource,
    metrics: CellPixelMetrics,
    rawPixel: PixelPoint? = nil
  ) -> PointerLocation {
    PointerLocation(
      location: location,
      cell: location.containingCell,
      precision: .subCell(source: source, metrics: metrics),
      rawPixel: rawPixel
    )
  }
}
