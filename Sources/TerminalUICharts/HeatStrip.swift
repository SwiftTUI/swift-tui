import Core
import View

/// A compact strip of heat-style cells for relative intensity data.
public struct HeatStrip<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var cellWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    entries: [BarChartEntry],
    cellWidth: Int = 2,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.cellWidth = cellWidth
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
          heatStripBody(
            entries: entries,
            maximumValue: maximumValue,
            cellWidth: cellWidth
          )
        },
        in: context
      )
    ]
  }
}

extension HeatStrip where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    self.init(
      entries: entries,
      cellWidth: cellWidth,
      label: { EmptyView() },
      summary: { Text(heatStripSummaryText(entries)) }
    )
  }
}

extension HeatStrip where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    cellWidth: Int = 2
  ) {
    self.init(
      entries: entries,
      cellWidth: cellWidth,
      label: { Text(String(title)) },
      summary: { Text(heatStripSummaryText(entries)) }
    )
  }
}
