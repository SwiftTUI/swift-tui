package import Core

// AnyView policy: retain heterogeneous child storage here for authored labels
// and current-value content.
/// A compact progress bar with optional label and current-value content.
public struct ProgressView: View, ResolvableView {
  public var value: Double
  public var total: Double
  public var barWidth: Int
  public private(set) var isIndeterminate: Bool
  private var labelViews: [AnyView]
  private var currentValueViews: [AnyView]

  /// Creates an indeterminate progress view with no label.
  public init(barWidth: Int = 12) {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    labelViews = []
    currentValueViews = []
  }

  /// Creates an indeterminate progress view with a label.
  public init<S: StringProtocol>(
    _ title: S,
    barWidth: Int = 12
  ) {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    labelViews = [AnyView(Text(String(title)))]
    currentValueViews = []
  }

  /// Creates an indeterminate progress view with a custom label.
  public init<Label: View>(
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label
  ) {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    labelViews = declaredBuilderChildren(from: label())
    currentValueViews = []
  }

  public init(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) {
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
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
    isIndeterminate = false
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
    isIndeterminate = false
    labelViews = declaredBuilderChildren(from: label())
    currentValueViews = declaredBuilderChildren(from: currentValueLabel())
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    AnyView(
      isIndeterminate
        ? indeterminateProgressView(
          labelViews: labelViews,
          barWidth: barWidth,
          phaseSeed: context.transaction.debugSignature,
          accentStyle: AnyShapeStyle(.tint)
        )
        : metricTrackView(
          labelViews: labelViews,
          trailingViews: currentValueViews,
          fraction: progressFraction(value: value, total: total),
          barWidth: barWidth,
          accentStyle: AnyShapeStyle(.tint)
        )
    ).resolveElements(in: context)
  }
}

@MainActor
private func indeterminateProgressView(
  labelViews: [AnyView],
  barWidth: Int,
  phaseSeed: String,
  accentStyle: AnyShapeStyle
) -> AnyView {
  let track = indeterminateProgressTrack(
    barWidth: barWidth,
    phaseSeed: phaseSeed
  )

  return AnyView(
    VStack(alignment: .leading, spacing: 0) {
      if !labelViews.isEmpty {
        combinedView(from: labelViews, kindName: "ProgressTrackLabel")
          .foregroundStyle(.terminalBorder(.accent))
      }
      HStack(alignment: .center, spacing: 0) {
        Text(track.leading)
          .foregroundStyle(.separator)
        Text(track.band)
          .foregroundStyle(accentStyle)
        Text(track.trailing)
          .foregroundStyle(.separator)
      }
    }
  )
}

private func indeterminateProgressTrack(
  barWidth: Int,
  phaseSeed: String
) -> (leading: String, band: String, trailing: String) {
  let segmentCount = max(1, barWidth)
  let bandCount = max(1, (segmentCount + 2) / 3)
  let travelCount = max(1, segmentCount - bandCount + 1)
  let offset = stableTrackPhase(for: phaseSeed, modulo: travelCount)
  return (
    leading: String(repeating: "─", count: offset),
    band: String(repeating: "█", count: bandCount),
    trailing: String(repeating: "─", count: segmentCount - offset - bandCount)
  )
}

private func stableTrackPhase(
  for seed: String,
  modulo: Int
) -> Int {
  guard modulo > 0 else {
    return 0
  }

  let hash = seed.unicodeScalars.reduce(into: UInt64(0)) { partialResult, scalar in
    partialResult = partialResult &* 31 &+ UInt64(scalar.value)
  }
  return Int(hash % UInt64(modulo))
}
