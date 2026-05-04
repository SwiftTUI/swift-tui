import SwiftTUICore
import SwiftTUIViews

/// A vertical column chart for comparing labeled values.
public struct ColumnChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var chartHeight: Int
  public var columnWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.chartHeight = chartHeight
    self.columnWidth = columnWidth
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let maximumValue = max(1, entries.map { abs($0.value) }.max() ?? 1)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          columnChartBody(
            entries: entries,
            maximumValue: maximumValue,
            chartHeight: chartHeight,
            columnWidth: columnWidth
          )
        },
        in: context
      )
    ]
  }
}

extension ColumnChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2
  ) {
    self.init(
      entries: entries,
      chartHeight: chartHeight,
      columnWidth: columnWidth,
      label: { EmptyView() },
      summary: { Text(columnChartSummaryText(entries)) }
    )
  }
}

extension ColumnChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2
  ) {
    self.init(
      entries: entries,
      chartHeight: chartHeight,
      columnWidth: columnWidth,
      label: { Text(String(title)) },
      summary: { Text(columnChartSummaryText(entries)) }
    )
  }
}
