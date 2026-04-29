/// Policy for enabling sub-cell pointer coordinates from terminal protocols.
public enum PointerPrecisionPolicy: Equatable, Sendable {
  /// Always use integer terminal-cell mouse coordinates.
  case cellOnly
  /// Use sub-cell coordinates only when the host has proven support and metrics.
  case subCellWhenKnown
  /// Enable terminal pixel coordinates when reported cell metrics are available.
  case forceTerminalPixels
}

/// Runtime pointer input capabilities exposed to authored views.
public struct PointerInputCapabilities: Equatable, Sendable {
  public var precision: PointerPrecision
  public var supportsSubCellLocation: Bool
  public var supportsHover: Bool
  public var supportsPreciseScroll: Bool

  public init(
    precision: PointerPrecision = .cell,
    supportsHover: Bool = false,
    supportsPreciseScroll: Bool = false
  ) {
    self.precision = precision
    self.supportsSubCellLocation = precision.isSubCell
    self.supportsHover = supportsHover
    self.supportsPreciseScroll = supportsPreciseScroll
  }

  /// Conservative default for terminal SGR 1006 and tests that do not opt in.
  public static let cellOnly = PointerInputCapabilities()
}
