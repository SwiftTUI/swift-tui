import SwiftTUIViews

/// A horizontal bar chart for comparing labeled values.
public struct BarChart<Label: View, Summary: View>: View {
  public var entries: [BarChartEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    entries: [BarChartEntry],
    barWidth: Int,
    labelWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.entries = entries
    self.barWidth = barWidth
    self.labelWidth = labelWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  public var body: some View {
    let maximumValue = max(1, entries.map { abs($0.value) }.max() ?? 1)

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
    }
    .semanticMetadata(
      chartAccessibilityMetadata(
        kind: "BarChart",
        label: accessibilitySummary
      )
    )
  }
}

extension BarChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [BarChartEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    let summary = barChartSummaryText(entries)
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
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
    let title = String(title)
    let summary = barChartSummaryText(entries)
    self.init(
      entries: entries,
      barWidth: barWidth,
      labelWidth: labelWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
