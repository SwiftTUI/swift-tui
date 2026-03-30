import Core
import View

/// A vertical column chart for comparing labeled values.
public struct ColumnChart: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var chartHeight: Int
  public var columnWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2
  ) {
    self.entries = entries
    self.chartHeight = chartHeight
    self.columnWidth = columnWidth
    labelViews = []
    summaryViews = [AnyView(Text(columnChartSummaryText(entries)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2
  ) {
    self.entries = entries
    self.chartHeight = chartHeight
    self.columnWidth = columnWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(columnChartSummaryText(entries)))]
  }

  public init<Label: View, Summary: View>(
    entries: [BarChartEntry],
    chartHeight: Int = 4,
    columnWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.chartHeight = chartHeight
    self.columnWidth = columnWidth
    labelViews = declaredBuilderChildren(from: label())
    summaryViews = declaredBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let maximumValue = max(1, entries.map { abs($0.value) }.max() ?? 1)

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "ColumnChartLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "ColumnChartSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        columnChartBody(
          entries: entries,
          maximumValue: maximumValue,
          chartHeight: chartHeight,
          columnWidth: columnWidth
        )
      }
    ).resolveElements(in: context)
  }
}
