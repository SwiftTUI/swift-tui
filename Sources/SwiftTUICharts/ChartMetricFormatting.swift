// Chart-local metric formatting helpers.
//
// These intentionally mirror the private formatting behavior of the
// framework's built-in metric controls (`ProgressView`, `Gauge`) so chart
// summaries and tracks render identically alongside them, without the chart
// library reaching into package-only framework internals.

func progressFraction(
  value: Double,
  total: Double
) -> Double {
  guard total > 0 else {
    return value > 0 ? 1 : 0
  }

  return min(max(value / total, 0), 1)
}

func metricValueString(
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

func progressSummaryText(
  value: Double,
  total: Double
) -> String {
  "\(metricValueString(value))/\(metricValueString(total))"
}

func meterSummaryText(
  value: Double,
  total: Double
) -> String {
  let percentage = Int((progressFraction(value: value, total: total) * 100).rounded())
  return "\(percentage)%"
}

func metricTrackString(
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
