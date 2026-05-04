import SwiftTUICore
import SwiftTUIViews

/// A gauge that changes tone across authored threshold bands.
public struct ThresholdGauge<Label: View, Summary: View>: View, ResolvableView {
  public var value: Double
  public var total: Double
  public var bands: [ThresholdBand]
  public var barWidth: Int
  private let label: Label
  private let summary: Summary

  public init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.value = value
    self.total = total
    self.bands = bands
    self.barWidth = barWidth
    self.label = label()
    self.summary = summary()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: summary)
          thresholdGaugeTrackView(
            value: value,
            total: total,
            bands: bands,
            barWidth: barWidth
          )
        },
        in: context
      )
    ]
  }
}

extension ThresholdGauge where Label == EmptyView, Summary == Text {
  public init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12
  ) {
    self.init(
      value: value,
      total: total,
      bands: bands,
      barWidth: barWidth,
      label: { EmptyView() },
      summary: { Text(progressSummaryText(value: value, total: total)) }
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
    self.init(
      value: value,
      total: total,
      bands: bands,
      barWidth: barWidth,
      label: { Text(String(title)) },
      summary: { Text(progressSummaryText(value: value, total: total)) }
    )
  }
}
