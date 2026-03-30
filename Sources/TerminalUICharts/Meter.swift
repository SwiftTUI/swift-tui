import Core
import View

/// A compact meter for displaying a single fractional value.
public struct Meter<Label: View, CurrentValueLabel: View>: View, ResolvableView {
  public var tone: BannerTone
  public var value: Double
  public var total: Double
  public var barWidth: Int
  private let label: Label
  private let currentValueLabel: CurrentValueLabel

  public init(
    value: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    self.tone = tone
    self.value = value
    self.total = total
    self.barWidth = barWidth
    self.label = label()
    self.currentValueLabel = currentValueLabel()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let track = metricTrackString(
      fraction: progressFraction(value: value, total: total),
      barWidth: barWidth
    )

    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: currentValueLabel)
          HStack(alignment: .center, spacing: 0) {
            Text(track.filled)
              .foregroundStyle(metricAccentStyle(for: tone))
            Text(track.empty)
              .foregroundStyle(.separator)
          }
        },
        in: context
      )
    ]
  }
}

extension Meter where Label == EmptyView, CurrentValueLabel == Text {
  public init(
    value: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    self.init(
      value: value,
      total: total,
      tone: tone,
      barWidth: barWidth,
      label: { EmptyView() },
      currentValueLabel: { Text(meterSummaryText(value: value, total: total)) }
    )
  }
}

extension Meter where Label == Text, CurrentValueLabel == Text {
  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    self.init(
      value: value,
      total: total,
      tone: tone,
      barWidth: barWidth,
      label: { Text(String(title)) },
      currentValueLabel: { Text(meterSummaryText(value: value, total: total)) }
    )
  }
}
