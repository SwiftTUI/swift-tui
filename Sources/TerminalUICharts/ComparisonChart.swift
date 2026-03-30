import Core
import View

/// A chart that shows current values against baselines.
public struct ComparisonChart: View, ResolvableView {
  public var entries: [ComparisonEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    labelViews = []
    summaryViews = [AnyView(Text(comparisonChartSummaryText(entries)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(comparisonChartSummaryText(entries)))]
  }

  public init<Label: View, Summary: View>(
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    labelViews = parallelBuilderChildren(from: label())
    summaryViews = parallelBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let maximumValue = comparisonChartMaximumValue(entries)

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "ComparisonChartLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "ComparisonChartSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        ForEach(entries.indices, id: \.self) { index in
          comparisonChartRow(
            entries[index],
            maximumValue: maximumValue,
            barWidth: barWidth,
            labelWidth: labelWidth
          )
        }
      }
    ).resolveElements(in: context)
  }
}
