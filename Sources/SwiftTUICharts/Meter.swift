import SwiftTUICore
import SwiftTUIViews

/// A compact meter for displaying a single fractional value.
public struct Meter<Label: View, CurrentValueLabel: View>: View, ResolvableView {
  public var tone: BannerTone
  public var value: Double
  public var total: Double
  public var barWidth: Int
  private let label: Label
  private let currentValueLabel: CurrentValueLabel
  private let accessibilitySummary: String?

  public init(
    value: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    self.init(
      value: value,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: nil,
      label: label,
      currentValueLabel: currentValueLabel
    )
  }

  private init(
    value: Double,
    total: Double,
    tone: BannerTone,
    barWidth: Int,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
    self.tone = tone
    self.value = value
    self.total = total
    self.barWidth = barWidth
    self.label = label()
    self.currentValueLabel = currentValueLabel()
    self.accessibilitySummary = accessibilitySummary
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
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "Meter",
            label: accessibilitySummary
          )
        ),
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
    let summary = meterSummaryText(value: value, total: total)
    self.init(
      value: value,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: summary,
      label: { EmptyView() },
      currentValueLabel: { Text(summary) }
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
    let title = String(title)
    let summary = meterSummaryText(value: value, total: total)
    self.init(
      value: value,
      total: total,
      tone: tone,
      barWidth: barWidth,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      currentValueLabel: { Text(summary) }
    )
  }
}
