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
