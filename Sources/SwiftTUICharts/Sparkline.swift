import SwiftTUICore
import SwiftTUIViews

/// A compact trend line rendered in terminal cells.
public struct Sparkline<Label: View, Summary: View>: View, ResolvableView {
  public var tone: BannerTone
  public var values: [Double]
  private let label: Label
  private let trailing: Summary

  public init(
    values: [Double],
    tone: BannerTone = .automatic,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.tone = tone
    self.values = values
    self.label = label()
    self.trailing = summary()
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
        },
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
    self.init(
      values: values,
      tone: tone,
      label: { EmptyView() },
      summary: { Text(sparklineSummaryText(values)) }
    )
  }
}

extension Sparkline where Label == Text, Summary == Text {
  public init<S: StringProtocol>(
    _ title: S,
    values: [Double],
    tone: BannerTone = .automatic
  ) {
    self.init(
      values: values,
      tone: tone,
      label: { Text(String(title)) },
      summary: { Text(sparklineSummaryText(values)) }
    )
  }
}
