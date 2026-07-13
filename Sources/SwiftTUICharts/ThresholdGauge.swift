import SwiftTUIViews

/// A gauge that changes tone across authored threshold bands.
public struct ThresholdGauge<Label: View, Summary: View>: View {
  public var value: Double
  public var total: Double
  public var bands: [ThresholdBand]
  public var barWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      value: value,
      total: total,
      bands: bands,
      barWidth: barWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.value = value
    self.total = total
    self.bands = bands
    self.barWidth = barWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  public var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      chartHeader(label: label, summary: summary)
      thresholdGaugeTrackView(
        value: value,
        total: total,
        bands: bands,
        barWidth: barWidth
      )
    }
    .semanticMetadata(
      chartAccessibilityMetadata(
        kind: "ThresholdGauge",
        label: accessibilitySummary
      )
    )
  }
}

extension ThresholdGauge where Label == EmptyView, Summary == Text {
  public init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12
  ) {
    let summary = progressSummaryText(value: value, total: total)
    self.init(
      value: value,
      total: total,
      bands: bands,
      barWidth: barWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension ThresholdGauge where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12
  ) {
    let title = String(title)
    let summary = progressSummaryText(value: value, total: total)
    self.init(
      value: value,
      total: total,
      bands: bands,
      barWidth: barWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
