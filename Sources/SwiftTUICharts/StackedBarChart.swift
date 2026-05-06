import SwiftTUICore
import SwiftTUIViews

/// A stacked bar chart for segmented totals.
public struct StackedBarChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var total: Double?
  public var barWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      entries: entries,
      total: total,
      barWidth: barWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    entries: [BarChartEntry],
    total: Double?,
    barWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.total = total
    self.barWidth = barWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let effectiveTotal = stackedBarEffectiveTotal(entries, total: total)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          stackedBarTrackView(
            entries,
            total: effectiveTotal,
            barWidth: barWidth
          )
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "StackedBarChart",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }
}

extension StackedBarChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16
  ) {
    let summary = stackedBarSummaryText(entries, total: total)
    self.init(
      entries: entries,
      total: total,
      barWidth: barWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension StackedBarChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16
  ) {
    let title = String(title)
    let summary = stackedBarSummaryText(entries, total: total)
    self.init(
      entries: entries,
      total: total,
      barWidth: barWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
