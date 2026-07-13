import SwiftTUIViews

/// A chart that shows current values against baselines.
public struct ComparisonChart<Label: View, Summary: View>: View {
  public var entries: [ComparisonEntry]
  public var barWidth: Int
  public var labelWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    entries: [ComparisonEntry],
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
    entries: [ComparisonEntry],
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
    let maximumValue = comparisonChartMaximumValue(entries)

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
    }
    .semanticMetadata(
      chartAccessibilityMetadata(
        kind: "ComparisonChart",
        label: accessibilitySummary
      )
    )
  }
}

extension ComparisonChart where Label == EmptyView, Summary == Text {
  public init(
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    let summary = comparisonChartSummaryText(entries)
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

extension ComparisonChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    entries: [ComparisonEntry],
    barWidth: Int = 12,
    labelWidth: Int = 8
  ) {
    let title = String(title)
    let summary = comparisonChartSummaryText(entries)
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
