import SwiftTUICore
import SwiftTUIViews

/// A vertical column chart for comparing labeled values.
public struct ColumnChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var chartHeight: Int
  public var columnWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      entries: entries,
      chartHeight: chartHeight,
      columnWidth: columnWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    entries: [BarChartEntry],
    chartHeight: Int,
    columnWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.chartHeight = chartHeight
    self.columnWidth = columnWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
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
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "ColumnChart",
            label: accessibilitySummary
          )
        ),
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
    let summary = columnChartSummaryText(entries)
    self.init(
      entries: entries,
      chartHeight: chartHeight,
      columnWidth: columnWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
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
    let title = String(title)
    let summary = columnChartSummaryText(entries)
    self.init(
      entries: entries,
      chartHeight: chartHeight,
      columnWidth: columnWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
