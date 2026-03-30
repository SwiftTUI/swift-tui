package import Core

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
package func metricTrackView(
  labelViews: [AnyView],
  trailingViews: [AnyView],
  fraction: Double,
  barWidth: Int,
  accentStyle: AnyShapeStyle
) -> AnyView {
  let track = metricTrackString(fraction: fraction, barWidth: barWidth)

  return AnyView(
    VStack(alignment: .leading, spacing: 0) {
      if !labelViews.isEmpty || !trailingViews.isEmpty {
        HStack(alignment: .center, spacing: 1) {
          if !labelViews.isEmpty {
            combinedView(from: labelViews, kindName: "MetricTrackLabel")
              .foregroundStyle(.terminalBorder(.accent))
          }
          if !trailingViews.isEmpty {
            Spacer()
            combinedView(from: trailingViews, kindName: "MetricTrackSummary")
              .foregroundStyle(.separator)
          }
        }
      }
      HStack(alignment: .center, spacing: 0) {
        Text(track.filled)
          .foregroundStyle(accentStyle)
        Text(track.empty)
          .foregroundStyle(.separator)
      }
    }
  )
}
