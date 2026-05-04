import SwiftTUICore
import SwiftTUIViews

/// A stacked bar chart for segmented totals.
public struct StackedBarChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var total: Double?
  public var barWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.total = total
    self.barWidth = barWidth
    self.label = label()
    self.summary = summary()
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
        },
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
    self.init(
      entries: entries,
      total: total,
      barWidth: barWidth,
      label: { EmptyView() },
      summary: { Text(stackedBarSummaryText(entries, total: total)) }
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
    self.init(
      entries: entries,
      total: total,
      barWidth: barWidth,
      label: { Text(String(title)) },
      summary: { Text(stackedBarSummaryText(entries, total: total)) }
    )
  }
}
