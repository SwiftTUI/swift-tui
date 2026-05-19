import SwiftTUICore
import SwiftTUIViews

// Comparison-chart helpers: maximum-value and summary derivation, automatic
// trend tone, the current-vs-baseline track renderer, and the labelled row.
//
// Split out of `ChartSupport.swift` so that file is not a catch-all for every
// chart family.

func comparisonChartMaximumValue(
  _ entries: [ComparisonEntry]
) -> Double {
  max(
    1,
    entries.map { entry in
      entry.total ?? max(abs(entry.current), abs(entry.baseline))
    }.max() ?? 1
  )
}

func comparisonChartSummaryText(
  _ entries: [ComparisonEntry]
) -> String {
  "max \(metricValueString(comparisonChartMaximumValue(entries)))"
}

func comparisonEntryTone(
  _ entry: ComparisonEntry
) -> BannerTone {
  guard entry.tone == .automatic else {
    return entry.tone
  }

  return trendTone(value: entry.current - entry.baseline, preferred: .automatic)
}

@MainActor
@ViewBuilder
func comparisonTrackView(
  current: Double,
  baseline: Double,
  total: Double,
  barWidth: Int,
  tone: BannerTone
) -> some View {
  let segmentCount = max(1, barWidth)
  let effectiveTotal = max(1, total)
  let currentCount = min(
    segmentCount,
    max(
      0,
      Int(
        (progressFraction(value: abs(current), total: effectiveTotal) * Double(segmentCount))
          .rounded()))
  )
  let baselineIndex = min(
    segmentCount - 1,
    max(
      0,
      Int(
        (progressFraction(value: abs(baseline), total: effectiveTotal)
          * Double(max(1, segmentCount - 1))).rounded())
    )
  )
  let accentStyle = metricAccentStyle(for: tone)

  HStack(alignment: .center, spacing: 0) {
    ForEach(0..<segmentCount, id: \.self) { index in
      if index == baselineIndex {
        Text(index < currentCount ? "◆" : "◇")
          .foregroundStyle(.info)
      } else if index < currentCount {
        Text("█")
          .foregroundStyle(accentStyle)
      } else {
        Text("─")
          .foregroundStyle(.separator)
      }
    }
  }
}

@MainActor
@ViewBuilder
func comparisonChartRow(
  _ entry: ComparisonEntry,
  maximumValue: Double,
  barWidth: Int,
  labelWidth: Int
) -> some View {
  let effectiveTotal = max(1, entry.total ?? maximumValue)
  let tone = comparisonEntryTone(entry)

  HStack(alignment: .center, spacing: 1) {
    Text(entry.label)
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(.foreground)
      .frame(width: max(1, labelWidth), height: 1, alignment: .leading)
    comparisonTrackView(
      current: entry.current,
      baseline: entry.baseline,
      total: effectiveTotal,
      barWidth: barWidth,
      tone: tone
    )
    Text("\(metricValueString(entry.current))/\(metricValueString(entry.baseline))")
      .foregroundStyle(.separator)
  }
}
