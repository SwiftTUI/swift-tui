import Core
import View

// AnyView policy: retain heterogeneous child storage here for authored label
// and summary content.
/// A gauge that changes tone across authored threshold bands.
public struct ThresholdGauge: View, ResolvableView {
  public var value: Double
  public var total: Double
  public var bands: [ThresholdBand]
  public var barWidth: Int
  private var labelViews: [AnyView]
  private var summaryViews: [AnyView]

  public init(
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12
  ) {
    self.value = value
    self.total = total
    self.bands = bands
    self.barWidth = barWidth
    labelViews = []
    summaryViews = [AnyView(Text(progressSummaryText(value: value, total: total)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double,
    bands: [ThresholdBand],
    barWidth: Int = 12
  ) {
    self.value = value
    self.total = total
    self.bands = bands
    self.barWidth = barWidth
    labelViews = [AnyView(Text(String(title)))]
    summaryViews = [AnyView(Text(progressSummaryText(value: value, total: total)))]
  }

  public init<Label: View, Summary: View>(
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
    labelViews = declaredBuilderChildren(from: label())
    summaryViews = declaredBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !summaryViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "ThresholdGaugeLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !summaryViews.isEmpty {
              Spacer()
              combinedView(from: summaryViews, kindName: "ThresholdGaugeSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        thresholdGaugeTrackView(
          value: value,
          total: total,
          bands: bands,
          barWidth: barWidth
        )
      }
    ).resolveElements(in: context)
  }
}
