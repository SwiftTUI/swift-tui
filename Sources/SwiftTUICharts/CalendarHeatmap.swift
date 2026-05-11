public import Foundation
import SwiftTUICore
import SwiftTUIViews

/// A GitHub-style weekday × week intensity grid for daily activity data.
public struct CalendarHeatmap<Label: View, Summary: View>: PrimitiveView, ResolvableView {
  public var days: [DateValue]
  public var range: ClosedRange<Date>?
  public var weekStart: CalendarHeatmapWeekStart
  public var calendar: Calendar
  public var cellWidth: Int
  public var showsMonthHeader: Bool
  public var showsDayLabels: Bool
  public var showsScaleLegend: Bool
  public var tone: BannerTone

  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    // Even when the caller supplies their own label/summary views, we
    // still want a synthesized accessibility summary so VoiceOver users
    // hear a meaningful description. The convenience inits below
    // override this when they have a title to compose with.
    let summarizedDayCount = "\(days.count) days"
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: summarizedDayCount,
      label: label,
      summary: summary
    )
  }

  private init(
    days: [DateValue],
    range: ClosedRange<Date>?,
    weekStart: CalendarHeatmapWeekStart,
    calendar: Calendar,
    cellWidth: Int,
    showsMonthHeader: Bool,
    showsDayLabels: Bool,
    showsScaleLegend: Bool,
    tone: BannerTone,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.days = days
    self.range = range
    self.weekStart = weekStart
    self.calendar = calendar
    self.cellWidth = cellWidth
    self.showsMonthHeader = showsMonthHeader
    self.showsDayLabels = showsDayLabels
    self.showsScaleLegend = showsScaleLegend
    self.tone = tone
    self.accessibilitySummary = accessibilitySummary
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let effectiveRange = range ?? inferDateRange(days) ?? Self.fallbackRange()
    let bucket = bucketDays(days, range: effectiveRange, calendar: calendar, weekStart: weekStart)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          calendarHeatmapBody(
            bucket: bucket,
            cellWidth: cellWidth,
            tone: tone,
            showsMonthHeader: showsMonthHeader,
            showsDayLabels: showsDayLabels,
            showsScaleLegend: showsScaleLegend
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "CalendarHeatmap",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }

  private static func fallbackRange() -> ClosedRange<Date> {
    let now = Date()
    return now...now
  }
}

extension CalendarHeatmap where Label == EmptyView, Summary == Text {
  public init(
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic
  ) {
    let summary = "\(days.count) days"
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension CalendarHeatmap where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    days: [DateValue],
    range: ClosedRange<Date>? = nil,
    weekStart: CalendarHeatmapWeekStart = .sunday,
    calendar: Calendar = .current,
    cellWidth: Int = 1,
    showsMonthHeader: Bool = true,
    showsDayLabels: Bool = true,
    showsScaleLegend: Bool = true,
    tone: BannerTone = .automatic
  ) {
    let title = String(title)
    let summary = "\(days.count) days"
    self.init(
      days: days,
      range: range,
      weekStart: weekStart,
      calendar: calendar,
      cellWidth: cellWidth,
      showsMonthHeader: showsMonthHeader,
      showsDayLabels: showsDayLabels,
      showsScaleLegend: showsScaleLegend,
      tone: tone,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}

extension CalendarHeatmap {
  /// Toggle the "Less ░ ▒ ▓ █ More" scale legend below the grid.
  /// `.hidden` clears it; `.bottom` / `.top` keep it visible (position
  /// is currently fixed at the bottom for `CalendarHeatmap`).
  public func chartLegend(_ config: LineChartLegendConfig) -> Self {
    var copy = self
    copy.showsScaleLegend = (config.position != .hidden)
    return copy
  }
}
