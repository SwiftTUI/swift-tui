import SwiftTUICore

package func progressFraction(
  value: Double,
  total: Double
) -> Double {
  guard !value.isNaN else { return 0 }
  guard total > 0 else {
    return value > 0 ? 1 : 0
  }

  let fraction = value / total
  return fraction.isNaN ? 0 : min(max(fraction, 0), 1)
}

package func metricValueString(
  _ value: Double
) -> String {
  guard value.isFinite else { return "0" }
  // One decimal is useful for ordinary counts, but a fixed decimal place
  // cannot describe sub-unit totals. Keep their significant digits.
  let rounded =
    abs(value) >= 1 && (value * 10).isFinite
    ? (value * 10).rounded() / 10 : value
  return trimmedControlString(rounded)
}

package func progressSummaryText(
  value: Double,
  total: Double
) -> String {
  let rawFraction = progressFraction(value: value, total: total)
  let fraction = rawFraction.isFinite ? rawFraction : 0
  guard total.isFinite, total > 0 else {
    return "\(Int((fraction * 100).rounded()))%"
  }
  return "\(metricValueString(fraction * total))/\(metricValueString(total))"
}

package func meterSummaryText(
  value: Double,
  total: Double
) -> String {
  let percentage = Int((progressFraction(value: value, total: total) * 100).rounded())
  return "\(percentage)%"
}

package func metricTrackString(
  fraction: Double,
  barWidth: Int
) -> (filled: String, empty: String) {
  let segmentCount = max(1, barWidth)
  let normalized = fraction.isNaN ? 0 : min(max(fraction, 0), 1)
  let filledCount =
    normalized >= 1
    ? segmentCount
    : min(segmentCount, max(0, Int((normalized * Double(segmentCount)).rounded())))
  let emptyCount = max(0, segmentCount - filledCount)
  return (
    filled: String(repeating: "█", count: filledCount),
    empty: String(repeating: "─", count: emptyCount)
  )
}

@MainActor
package func isEmptyView<V: View>(
  _ view: V
) -> Bool {
  let erased: Any = view
  return erased is EmptyView
}

@MainActor
@ViewBuilder
package func metricChartHeader<Label: View, Summary: View>(
  label: Label,
  summary: Summary
) -> some View {
  if !isEmptyView(label) || !isEmptyView(summary) {
    HStack(alignment: .center, spacing: 1) {
      if !isEmptyView(label) {
        label
          .foregroundStyle(.terminalBorder(.accent))
      }
      if !isEmptyView(summary) {
        Spacer()
        summary
          .foregroundStyle(.separator)
      }
    }
  }
}

@MainActor
@ViewBuilder
package func metricTrackView<Label: View, Trailing: View>(
  label: Label,
  trailing: Trailing,
  fraction: Double,
  barWidth: Int,
  accentStyle: AnyShapeStyle
) -> some View {
  let track = metricTrackString(fraction: fraction, barWidth: barWidth)

  VStack(alignment: .leading, spacing: 0) {
    metricChartHeader(label: label, summary: trailing)
    HStack(alignment: .center, spacing: 0) {
      Text(track.filled)
        .foregroundStyle(accentStyle)
      Text(track.empty)
        .foregroundStyle(.separator)
    }
  }
}
