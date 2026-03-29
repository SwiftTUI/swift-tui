import Core
import View

/// A horizontal bar chart for comparing labeled values.
public struct BarChart: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    labelViews = []
    summaryViews = [AnyView(Text(barChartSummaryText(entries)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(barChartSummaryText(entries)))]
  }

  public init<Label: View, Summary: View>(
    entries: [BarChartEntry],
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
    let maximumValue = max(1, entries.map { abs($0.value) }.max() ?? 1)

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "BarChartLabel")
                .foregroundStyle(.muted)
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "BarChartSummary")
                .foregroundStyle(.muted)
            }
          }
        }
        ForEach(entries.indices, id: \.self) { index in
          barChartRow(
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
