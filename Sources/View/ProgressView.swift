package import Core

/// A compact progress bar with optional label and current-value content.
public struct ProgressView: View, ResolvableView {
  public var value: Double
  public var total: Double
  public var barWidth: Int
  private var labelViews: [AnyView]
  private var currentValueViews: [AnyView]

  public init(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) {
    self.value = value
    self.total = total
    self.barWidth = barWidth
    labelViews = []
    currentValueViews = [AnyView(Text(progressSummaryText(value: value, total: total)))]
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) {
    self.value = value
    self.total = total
    self.barWidth = barWidth
    labelViews = [AnyView(Text(String(title)))]
    currentValueViews = [AnyView(Text(progressSummaryText(value: value, total: total)))]
  }

  public init<Label: View, CurrentValueLabel: View>(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label,
    @ViewBuilder currentValueLabel: () -> CurrentValueLabel
  ) {
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
        accentStyle: AnyShapeStyle(.tint)
      )
    ).resolveElements(in: context)
  }
}
