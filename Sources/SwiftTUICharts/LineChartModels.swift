public import Foundation

/// A `(x, y)` point in a line chart's continuous coordinate space.
public struct LineChartPoint: Hashable, Sendable {
  public var x: Double
  public var y: Double

  public init(x: Double, y: Double) {
    self.x = x
    self.y = y
  }
}

extension LineChartPoint {
  /// Convenience initializer that maps a `Date` to `x` via
  /// `timeIntervalSinceReferenceDate`. The X-axis formatter decides whether
  /// `x` is rendered as a date or as a number.
  public init(date: Date, value: Double) {
    self.init(x: date.timeIntervalSinceReferenceDate, y: value)
  }
}
