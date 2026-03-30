import Core
import View

/// A compact trend line rendered in terminal cells.
public struct Sparkline: View, ResolvableView {
  public var tone: BannerTone
  public var values: [Double]
  private var labelViews: [AnyView]
  private var trailingViews: [AnyView]

  public init(
    values: [Double],
    tone: BannerTone = .automatic
  ) {
    self.tone = tone
    self.values = values
    labelViews = []
    trailingViews = [AnyView(Text(sparklineSummaryText(values)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    values: [Double],
    tone: BannerTone = .automatic
  ) {
    self.tone = tone
    self.values = values
    labelViews = [AnyView(Text(String(title)))]
    trailingViews = [AnyView(Text(sparklineSummaryText(values)))]
  }

  public init<Label: View, Summary: View>(
    values: [Double],
    tone: BannerTone = .automatic,
    @ViewBuilder label: () -> Label,
    @ViewBuilder summary: () -> Summary
  ) {
    self.tone = tone
    self.values = values
    labelViews = parallelBuilderChildren(from: label())
    trailingViews = parallelBuilderChildren(from: summary())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      VStack(alignment: .leading, spacing: 0) {
        if !labelViews.isEmpty || !trailingViews.isEmpty {
          HStack(alignment: .center, spacing: 1) {
            if !labelViews.isEmpty {
              combinedView(from: labelViews, kindName: "SparklineLabel")
                .foregroundStyle(.terminalBorder(.accent))
            }
            if !trailingViews.isEmpty {
              Spacer()
              combinedView(from: trailingViews, kindName: "SparklineSummary")
                .foregroundStyle(.separator)
            }
          }
        }
        Text(sparklineGlyphString(values))
          .foregroundStyle(metricAccentStyle(for: tone))
      }
    ).resolveElements(in: context)
  }
}
