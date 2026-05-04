package import SwiftTUICore

package func progressFraction(
  value: Double,
  total: Double
) -> Double {
  guard total > 0 else {
    return value > 0 ? 1 : 0
  }

  return min(max(value / total, 0), 1)
}

package func metricValueString(
  _ value: Double
) -> String {
  if value.isNaN || value.isInfinite {
    return "0"
  }

  let rounded = value.rounded()
  if abs(rounded - value) < 0.000_1 {
    return String(Int(rounded))
  }

  let scaled = (value * 10).rounded() / 10
  let sign = scaled < 0 ? "-" : ""
  let absolute = abs(scaled)
  let whole = Int(absolute.rounded(.towardZero))
  let fractional = Int((absolute * 10).rounded()) % 10
  return "\(sign)\(whole).\(fractional)"
}

package func progressSummaryText(
  value: Double,
  total: Double
) -> String {
  "\(metricValueString(value))/\(metricValueString(total))"
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
  let filledCount = min(
    segmentCount,
    max(0, Int((fraction * Double(segmentCount)).rounded()))
  )
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
