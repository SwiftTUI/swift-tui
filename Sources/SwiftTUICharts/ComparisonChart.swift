import SwiftTUICore
import SwiftTUIViews

/// A chart that shows current values against baselines.
public struct ComparisonChart<Label: View, Summary: View>: View, ResolvableView {
  public var entries: [ComparisonEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    entries: [ComparisonEntry],
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
    let maximumValue = comparisonChartMaximumValue(entries)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          ForEach(entries.indices, id: \.self) { index in
            comparisonChartRow(
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

extension ComparisonChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      label: { EmptyView() },
      summary: { Text(comparisonChartSummaryText(entries)) }
    )
  }
}

extension ComparisonChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      label: { Text(String(title)) },
      summary: { Text(comparisonChartSummaryText(entries)) }
    )
  }
}
