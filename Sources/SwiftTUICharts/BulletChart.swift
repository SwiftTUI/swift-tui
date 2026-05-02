import Core
import View

/// A bullet chart that compares a current value against a target or range.
public struct BulletChart<Label: View, Summary: View>: View, ResolvableView {
  public var value: Double
  public var target: Double
  public var total: Double
  public var tone: BannerTone
  public var barWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    value: Double,
    target: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12,
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
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let accentStyle = metricAccentStyle(for: tone)

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          bulletChartTrackView(
            value: value,
            target: target,
            total: total,
            barWidth: barWidth,
            accentStyle: accentStyle
          )
        },
        in: context
      )
    ]
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
    self.init(
      value: value,
      target: target,
      total: total,
      tone: tone,
      barWidth: barWidth,
      label: { EmptyView() },
      summary: { Text(bulletChartSummaryText(target: target)) }
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
    self.init(
      value: value,
      target: target,
      total: total,
      tone: tone,
      barWidth: barWidth,
      label: { Text(String(title)) },
      summary: { Text(bulletChartSummaryText(target: target)) }
    )
  }
}
