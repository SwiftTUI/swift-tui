public import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A single entry in a compact timeline view.
public struct TimelineEntry: Hashable, Sendable {
  public var title: String
  public var detail: String?
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ title: S,
    detail: String? = nil,
    tone: BannerTone = .automatic
  ) {
    self.title = String(title)
    self.detail = detail
    self.tone = tone
  }
}

/// A label and tone pairing used by legends and summaries.
public struct LegendItem: Hashable, Sendable {
  public var label: String
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ label: S,
    tone: BannerTone = .automatic
  ) {
    self.label = String(label)
    self.tone = tone
  }
}

/// A comparison entry with current and baseline values.
public struct ComparisonEntry: Hashable, Sendable {
  public var label: String
  public var current: Double
  public var baseline: Double
  public var total: Double?
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ label: S,
    current: Double,
    baseline: Double,
    total: Double? = nil,
    tone: BannerTone = .automatic
  ) {
    self.label = String(label)
    self.current = current
    self.baseline = baseline
    self.total = total
    self.tone = tone
  }
}

/// A labeled numeric value used by bar and column charts.
public struct BarChartEntry: Hashable, Sendable {
  public var label: String
  public var value: Double
  public var tone: BannerTone

  public init<S: StringProtocol>(
    _ label: S,
    value: Double,
    tone: BannerTone = .automatic
  ) {
    self.label = String(label)
    self.value = value
    self.tone = tone
  }
}

/// A threshold band used by gauges and status-oriented meters.
public struct ThresholdBand: Hashable, Sendable {
  public var upperBound: Double
  public var tone: BannerTone

  public init(
    upTo upperBound: Double,
    tone: BannerTone = .automatic
  ) {
    self.upperBound = upperBound
    self.tone = tone
  }
}

/// A date paired with a numeric value, used by date-axis charts.
public struct DateValue: Hashable, Sendable {
  public var date: Date
  public var value: Double

  public init(_ date: Date, value: Double) {
    self.date = date
    self.value = value
  }
}
