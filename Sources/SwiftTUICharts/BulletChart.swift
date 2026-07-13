import SwiftTUIViews

/// A bullet chart that compares a current value against a target or range.
public struct BulletChart<Label: View, Summary: View>: View {
  public var value: Double
  public var target: Double
  public var total: Double
  public var tone: BannerTone
  public var barWidth: Int
  private let label: Label
  private let summary: Summary
  private let accessibilitySummary: String?

  public init(
    value: Double,
    target: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      value: value,
      target: target,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    value: Double,
    target: Double,
    total: Double,
    tone: BannerTone,
    barWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.value = value
    self.target = target
    self.total = total
    self.tone = tone
    self.barWidth = barWidth
    self.label = label()
    self.summary = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  public var body: some View {
    let accentStyle = metricAccentStyle(for: tone)

    VStack(alignment: .leading, spacing: 0) {
      chartHeader(label: label, summary: summary)
      bulletChartTrackView(
        value: value,
        target: target,
        total: total,
        barWidth: barWidth,
        accentStyle: accentStyle
      )
    }
    .semanticMetadata(
      chartAccessibilityMetadata(
        kind: "BulletChart",
        label: accessibilitySummary
      )
    )
  }
}

extension BulletChart where Label == EmptyView, Summary == Text {
  public init(
    value: Double,
    target: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    let summary = bulletChartSummaryText(target: target)
    self.init(
      value: value,
      target: target,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension BulletChart where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    target: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    let title = String(title)
    let summary = bulletChartSummaryText(target: target)
    self.init(
      value: value,
      target: target,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
