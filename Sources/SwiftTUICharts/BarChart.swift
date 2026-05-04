import SwiftTUICore
import SwiftTUIViews

/// A horizontal bar chart for comparing labeled values.
public struct BarChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [BarChartEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
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
          ForEach(entries.indices, id: \.self) { index in
            barChartRow(
              entries[index],
              maximumValue: maximumValue,
              barWidth: barWidth,
              labelWidth: labelWidth
            )
          }
        },
        in: context
      )
    ]
  }
}

extension BarChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      label: { EmptyView() },
      summary: { Text(barChartSummaryText(entries)) }
    )
  }
}

extension BarChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      label: { Text(String(title)) },
      summary: { Text(barChartSummaryText(entries)) }
    )
  }
}
