import Core
import View

/// A stacked bar chart for segmented totals.
public struct StackedBarChart: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var total: Double?
  public var barWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16
  ) {
    self.entries = entries
    self.total = total
    self.barWidth = barWidth
    labelViews = []
    summaryViews = [AnyView(Text(stackedBarSummaryText(entries, total: total)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16
  ) {
    self.entries = entries
    self.total = total
    self.barWidth = barWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(stackedBarSummaryText(entries, total: total)))]
  }

  public init<Label: View, Summary: View>(
    entries: [BarChartEntry],
    total: Double? = nil,
    barWidth: Int = 16,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.total = total
    self.barWidth = barWidth
    labelViews = parallelBuilderChildren(from: label())
    summaryViews = parallelBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let effectiveTotal = stackedBarEffectiveTotal(entries, total: total)

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "StackedBarChartLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "StackedBarChartSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        stackedBarTrackView(
          entries,
          total: effectiveTotal,
          barWidth: barWidth
        )
      }
    ).resolveElements(in: context)
  }
}
