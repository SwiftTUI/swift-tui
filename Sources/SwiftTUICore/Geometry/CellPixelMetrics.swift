/// Read-only display metrics describing how cells map to device pixels.
///
/// Advisory runtime metadata. SwiftTUI's layout, placement, and alignment
/// story remain cell-denominated; this type exists so authors can apply
/// aspect correction to shapes, motion, or image sizing without reinventing
/// the fallback.
public struct CellPixelMetrics: Equatable, Hashable, Sendable {
  /// Width of a single cell in device pixels.
  public let width: Int
  /// Height of a single cell in device pixels.
  public let height: Int
  /// Confidence in the reported value.
  public let source: Source

  public init(width: Int, height: Int, source: Source) {
    self.width = width
    self.height = height
    self.source = source
  }

  /// Cell height divided by cell width. Conventionally ~2.0 for typical
  /// monospace fonts.
  public var aspectRatio: Double {
    Double(height) / Double(width)
  }

  public enum Source: Equatable, Hashable, Sendable {
    /// The terminal reported its cell size via `ioctl` or an escape query.
    case reported
    /// No cell size was reported; this is the conventional 8x16 fallback.
    case estimated
  }

  /// Conventional 8x16 fallback used when the terminal did not report its
  /// cell size. Aspect ratio 2:1.
  public static let estimated = Self(width: 8, height: 16, source: .estimated)
}
