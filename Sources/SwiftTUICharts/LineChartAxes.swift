public import Foundation

/// Calendar stride for the X axis when X is interpreted as a date.
public enum DateAxisStride: Hashable, Sendable {
  case day, week, month, quarter, year
}

/// Where `.area` and `.step` rasters anchor along Y.
public enum LineChartBaseline: Hashable, Sendable {
  /// Areas / step fills anchor at 0; clipped by the plot if 0 falls
  /// outside the visible Y range.
  case zero
  /// Areas / step fills anchor at `min(Y)` across visible series.
  case auto
}

/// X-axis configuration. Constructed via `.values(...)`, `.dates(...)`,
/// `.automatic`, or `.hidden`, then applied to a `LineChart` via
/// `.chartXAxis(_:)`.
public struct LineChartXAxis: Hashable, Sendable {
  public enum Ticks: Hashable, Sendable {
    /// ~5 evenly spaced ticks chosen by the renderer.
    case automatic
    /// Exactly `N` evenly spaced ticks across the plot.
    case count(Int)
    /// Approximately one tick per `stride` of domain. The number of ticks
    /// is derived from `span / stride`, but the ticks are then spaced
    /// evenly across the plot — they are not positioned at exact multiples
    /// of `stride`. Use `.dates(every:)` for calendar-boundary snapping.
    case every(stride: Double)
    /// Snaps ticks to calendar boundaries of the given stride
    /// (e.g., month starts).
    case dates(every: DateAxisStride)
  }

  public enum Format: Hashable, Sendable {
    case automatic
    case number(FloatingPointFormatStyle<Double>)
    case date(Date.FormatStyle)
  }

  public var ticks: Ticks
  public var format: Format
  public var isHidden: Bool

  public init(ticks: Ticks, format: Format, isHidden: Bool = false) {
    self.ticks = ticks
    self.format = format
    self.isHidden = isHidden
  }

  public static let automatic = Self(ticks: .automatic, format: .automatic)
  public static let hidden = Self(ticks: .automatic, format: .automatic, isHidden: true)

  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number
  ) -> Self {
    .init(ticks: .count(count), format: .number(format))
  }

  public static func dates(
    every stride: DateAxisStride,
    format: Date.FormatStyle = .dateTime.month(.abbreviated).day()
  ) -> Self {
    .init(ticks: .dates(every: stride), format: .date(format))
  }
}

/// Y-axis configuration. Same shape as `LineChartXAxis` without the
/// `.dates` tick / format variants.
public struct LineChartYAxis: Hashable, Sendable {
  public enum Ticks: Hashable, Sendable {
    /// ~5 evenly spaced ticks chosen by the renderer.
    case automatic
    /// Exactly `N` evenly spaced ticks across the plot.
    case count(Int)
    /// Approximately one tick per `stride` of domain. The number of ticks
    /// is derived from `span / stride`, but the ticks are then spaced
    /// evenly across the plot — they are not positioned at exact multiples
    /// of `stride`.
    case every(stride: Double)
  }

  public var ticks: Ticks
  public var format: FloatingPointFormatStyle<Double>
  public var isHidden: Bool

  public init(
    ticks: Ticks,
    format: FloatingPointFormatStyle<Double> = .number.notation(.compactName),
    isHidden: Bool = false
  ) {
    self.ticks = ticks
    self.format = format
    self.isHidden = isHidden
  }

  public static let automatic = Self(ticks: .automatic)
  public static let hidden = Self(ticks: .automatic, isHidden: true)

  public static func values(
    count: Int = 5,
    format: FloatingPointFormatStyle<Double> = .number.notation(.compactName)
  ) -> Self {
    .init(ticks: .count(count), format: format)
  }
}

/// Legend strip placement around the chart body.
public struct LineChartLegendConfig: Hashable, Sendable {
  public enum Position: Hashable, Sendable { case top, bottom, hidden }

  public var position: Position
  public var itemSpacing: Int

  public init(position: Position, itemSpacing: Int = 2) {
    self.position = position
    self.itemSpacing = itemSpacing
  }

  public static let bottom = Self(position: .bottom)
  public static let top = Self(position: .top)
  public static let hidden = Self(position: .hidden)
}
