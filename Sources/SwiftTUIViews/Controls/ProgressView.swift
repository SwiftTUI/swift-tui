package import SwiftTUICore

/// A compact progress bar with optional label and current-value content.
public struct ProgressView<Label: View, CurrentValueLabel: View>: View, ResolvableView {
  public var value: Double
  public var total: Double
  public var barWidth: Int
  public private(set) var isIndeterminate: Bool
  private var label: Label
  private var currentValueLabel: CurrentValueLabel

  /// Creates an indeterminate progress view with no label.
  public init(barWidth: Int = 12) where Label == EmptyView, CurrentValueLabel == EmptyView {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    label = EmptyView()
    currentValueLabel = EmptyView()
  }

  /// Creates an indeterminate progress view with a label.
  public init<S: StringProtocol>(
    _ title: S,
    barWidth: Int = 12
  ) where Label == Text, CurrentValueLabel == EmptyView {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    label = Text(String(title))
    currentValueLabel = EmptyView()
  }

  /// Creates an indeterminate progress view with a custom label.
  public init(
    barWidth: Int = 12,
    @ViewBuilder label: () -> Label
  ) where CurrentValueLabel == EmptyView {
    value = 0
    total = 0
    self.barWidth = barWidth
    isIndeterminate = true
    self.label = label()
    currentValueLabel = EmptyView()
  }

  public init(
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) where Label == EmptyView, CurrentValueLabel == Text {
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
    label = EmptyView()
    currentValueLabel = Text(progressSummaryText(value: value, total: total))
  }

  public init<S: StringProtocol>(
    _ title: S,
    value: Double,
    total: Double = 1,
    barWidth: Int = 12
  ) where Label == Text, CurrentValueLabel == Text {
    self.value = value
    self.total = total
    self.barWidth = barWidth
    isIndeterminate = false
    label = Text(String(title))
    currentValueLabel = Text(progressSummaryText(value: value, total: total))
  }

  public init(
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
    self.label = label()
    self.currentValueLabel = currentValueLabel()
  }

  package func resolveElements(
    in context: ResolveContext
  ) -> [ResolvedNode] {
    if isIndeterminate {
      return indeterminateProgressView(
        label: label,
        barWidth: barWidth,
        phaseSeed: context.transaction.debugSignature,
        accentStyle: AnyShapeStyle(.tint)
      ).resolveElements(in: context)
    }

    return metricTrackView(
      label: label,
      trailing: currentValueLabel,
      fraction: progressFraction(value: value, total: total),
      barWidth: barWidth,
      accentStyle: AnyShapeStyle(.tint)
    ).resolveElements(in: context)
  }
}

@MainActor
private func indeterminateProgressView<Label: View>(
  label: Label,
  barWidth: Int,
  phaseSeed: String,
  accentStyle: AnyShapeStyle
) -> some View {
  let track = indeterminateProgressTrack(
    barWidth: barWidth,
    phaseSeed: phaseSeed
  )

  return VStack(alignment: .leading, spacing: 0) {
    metricChartHeader(label: label, summary: EmptyView())
    HStack(alignment: .center, spacing: 0) {
      Text(track.leading)
        .foregroundStyle(.separator)
      Text(track.band)
        .foregroundStyle(accentStyle)
      Text(track.trailing)
        .foregroundStyle(.separator)
    }
  }
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
