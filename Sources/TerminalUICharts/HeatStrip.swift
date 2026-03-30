import Core
import View

/// A compact strip of heat-style cells for relative intensity data.
public struct HeatStrip: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var cellWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    self.entries = entries
    self.cellWidth = cellWidth
    labelViews = []
    summaryViews = [AnyView(Text(heatStripSummaryText(entries)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    self.entries = entries
    self.cellWidth = cellWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(heatStripSummaryText(entries)))]
  }

  public init<Label: View, Summary: View>(
    entries: [BarChartEntry],
    cellWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.cellWidth = cellWidth
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
              combinedView(from: labelViews, kindName: "HeatStripLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "HeatStripSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        heatStripBody(
          entries: entries,
          maximumValue: maximumValue,
          cellWidth: cellWidth
        )
      }
    ).resolveElements(in: context)
  }
}
