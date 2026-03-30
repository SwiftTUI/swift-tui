import Core
import View

/// A bullet chart that compares a current value against a target or range.
public struct BulletChart: View, ResolvableView {
  public var value: Double
  public var target: Double
  public var total: Double
  public var tone: BannerTone
  public var barWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    target: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    self.value = value
    self.target = target
    self.total = total
    self.tone = tone
    self.barWidth = barWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(bulletChartSummaryText(target: target)))]
  }

  public init<Label: View, Summary: View>(
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
    labelViews = declaredBuilderChildren(from: label())
    summaryViews = declaredBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let accentStyle = metricAccentStyle(for: tone)

    return AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "BulletChartLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "BulletChartSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        bulletChartTrackView(
          value: value,
          target: target,
          total: total,
          barWidth: barWidth,
          accentStyle: accentStyle
        )
      }
    ).resolveElements(in: context)
  }
}
