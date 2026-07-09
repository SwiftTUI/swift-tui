/// Canonical axes used by layout, scrolling, and charts.
public enum Axis: String, Equatable, Sendable {
  case horizontal
  case vertical
}

/// Option set describing the top and bottom edges of a vertical region.
public struct VerticalEdgeSet: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let top = Self(rawValue: 1 << 0)
  public static let bottom = Self(rawValue: 1 << 1)
  public static let all: Self = [.top, .bottom]
}

/// Option set describing horizontal and vertical participation.
public struct AxisSet: OptionSet, Equatable, Sendable {
  public let rawValue: UInt8

  public init(rawValue: UInt8) {
    self.rawValue = rawValue
  }

  public static let horizontal = Self(rawValue: 1 << 0)
  public static let vertical = Self(rawValue: 1 << 1)
}
