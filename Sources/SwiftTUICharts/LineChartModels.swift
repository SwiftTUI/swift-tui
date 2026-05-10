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

/// Rendering style for a single `LineChartSeries`.
public enum LineChartSeriesStyle: Hashable, Sendable {
  /// Single-cell line raster between consecutive samples.
  case line
  /// Same as `.line`, plus a shaded fill from the line down to the
  /// chart's baseline.
  case area
  /// Staircase between samples: horizontal segment at each sample's
  /// Y, then a vertical jump to the next sample's Y. No diagonal.
  case step
}

/// A labeled, toned series of `LineChartPoint`s.
public struct LineChartSeries: Hashable, Sendable {
  public var label: String
  public var points: [LineChartPoint]
  public var style: LineChartSeriesStyle
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ label: S,
    points: [LineChartPoint],
    style: LineChartSeriesStyle = .line,
    tone: BannerTone = .automatic
  ) {
    self.label = String(label)
    self.points = points
    self.style = style
    self.tone = tone
  }
}
