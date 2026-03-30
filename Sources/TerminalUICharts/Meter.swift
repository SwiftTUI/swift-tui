import Core
import View

// AnyView policy: retain heterogeneous child storage here for authored label
// and current-value content.
/// A compact meter for displaying a single fractional value.
public struct Meter: View, ResolvableView {
  public var tone: BannerTone
  public var value: Double
  public var total: Double
  public var barWidth: Int
  private var labelViews: [AnyView]
  private var currentValueViews: [AnyView]

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double = 1,
    tone: BannerTone = .automatic,
    barWidth: Int = 12
  ) {
    self.tone = tone
    self.value = value
    self.total = total
    self.barWidth = barWidth
    labelViews = [AnyView(Text(String(title)))]
    currentValueViews = [AnyView(Text(meterSummaryText(value: value, total: total)))]
  }

  public init<Label: View, CurrentValueLabel: View>(
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
    labelViews = declaredBuilderChildren(from: label())
    currentValueViews = declaredBuilderChildren(from: currentValueLabel())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      metricTrackView(
        labelViews: labelViews,
        trailingViews: currentValueViews,
        fraction: progressFraction(value: value, total: total),
        barWidth: barWidth,
        accentStyle: metricAccentStyle(for: tone)
      )
    ).resolveElements(in: context)
  }
}
