import SwiftTUICore
import SwiftTUIViews

/// A compact trend line rendered in terminal cells.
public struct Sparkline<Label: View, Summary: View>: View, ResolvableView {
  public var tone: BannerTone
  public var values: [Double]
  private let label: Label
  private let trailing: Summary
  private let accessibilitySummary: String?

  public init(
    values: [Double],
    tone: BannerTone = .automatic,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.init(
      values: values,
      tone: tone,
      accessibilitySummary: nil,
      label: label,
      summary: summary
    )
  }

  private init(
    values: [Double],
    tone: BannerTone,
    accessibilitySummary: String?,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.tone = tone
    self.values = values
    self.label = label()
    self.trailing = summary()
    self.accessibilitySummary = accessibilitySummary
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    return [
      resolveView(
        VStack(alignment: .leading, spacing: 0) {
          chartHeader(label: label, summary: trailing)
          Text(sparklineGlyphString(values))
            .foregroundStyle(metricAccentStyle(for: tone))
        }
        .semanticMetadata(
          chartAccessibilityMetadata(
            kind: "Sparkline",
            label: accessibilitySummary
          )
        ),
        in: context
      )
    ]
  }
}

extension Sparkline where Label == EmptyView, Summary == Text {
  public init(
    values: [Double],
    tone: BannerTone = .automatic
  ) {
    let summary = sparklineSummaryText(values)
    self.init(
      values: values,
      tone: tone,
      accessibilitySummary: summary,
      label: { EmptyView() },
      summary: { Text(summary) }
    )
  }
}

extension Sparkline where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    values: [Double],
    tone: BannerTone = .automatic
  ) {
    let title = String(title)
    let summary = sparklineSummaryText(values)
    self.init(
      values: values,
      tone: tone,
      accessibilitySummary: chartAccessibilityLabel(title: title, summary: summary),
      label: { Text(title) },
      summary: { Text(summary) }
    )
  }
}
