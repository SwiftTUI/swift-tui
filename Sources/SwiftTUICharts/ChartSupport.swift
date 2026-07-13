import SwiftTUIViews

// Shared chart helpers and the timeline/legend renderers live in
// `ChartCommonSupport.swift`. Per-family helpers live in their own
// `*ChartSupport.swift` files. This file retains the bar, column, and
// heat-strip helpers.

// Bullet-chart helpers live in `BulletChartSupport.swift`.

func barChartSummaryText(
  _ entries: [BarChartEntry]
) -> String {
  guard let maximum = entries.map({ abs($0.value) }).max() else {
    return "max 0"
  }

  return "max \(metricValueString(maximum))"
}

// Comparison-chart helpers live in `ComparisonChartSupport.swift`.

// Stacked-bar-chart helpers live in `StackedBarChartSupport.swift`.

func columnChartSummaryText(
  _ entries: [BarChartEntry]
) -> String {
  barChartSummaryText(entries)
}

// Threshold-gauge helpers live in `ThresholdGaugeSupport.swift`.

func heatStripSummaryText(
  _ entries: [BarChartEntry]
) -> String {
  guard let maximum = entries.map({ abs($0.value) }).max() else {
    return "0 cells"
  }

  return "hi \(metricValueString(maximum))"
}

func columnChartFilledHeight(
  value: Double,
  maximumValue: Double,
  chartHeight: Int
) -> Int {
  guard maximumValue > 0, chartHeight > 0 else {
    return 0
  }

  let normalized = min(max(abs(value) / maximumValue, 0), 1)
  if normalized == 0 {
    return 0
  }

  return min(chartHeight, max(1, Int((normalized * Double(chartHeight)).rounded(.awayFromZero))))
}

@MainActor
@ViewBuilder
func columnChartBody(
  entries: [BarChartEntry],
  maximumValue: Double,
  chartHeight: Int,
  columnWidth: Int
) -> some View {
  let effectiveHeight = max(1, chartHeight)
  let effectiveWidth = max(1, columnWidth)

  VStack(alignment: .leading, spacing: 0) {
    ForEach((0..<effectiveHeight).reversed(), id: \.self) { row in
      HStack(alignment: .center, spacing: 1) {
        ForEach(entries.indices, id: \.self) { index in
          let accentStyle =
            entries[index].tone == .automatic
            ? AnyShapeStyle(.tint)
            : metricAccentStyle(for: entries[index].tone)
          let filledHeight = columnChartFilledHeight(
            value: entries[index].value,
            maximumValue: maximumValue,
            chartHeight: effectiveHeight
          )

          Text(
            row < filledHeight
              ? String(repeating: "█", count: effectiveWidth)
              : String(repeating: " ", count: effectiveWidth)
          )
          .foregroundStyle(accentStyle)
          .frame(width: effectiveWidth, height: 1, alignment: .center)
        }
      }
    }
    HStack(alignment: .center, spacing: 1) {
      ForEach(entries.indices, id: \.self) { index in
        Text(String(entries[index].label.prefix(effectiveWidth)))
          .lineLimit(1)
          .foregroundStyle(.foreground)
          .frame(width: effectiveWidth, height: 1, alignment: .center)
      }
    }
  }
}

/// Maps a 0...1 intensity fraction to the canonical 4-step ramp glyph.
/// Returns `"░"` for < 0.25, `"▒"` for < 0.5, `"▓"` for < 0.75, `"█"` otherwise.
func intensityRampGlyph(fraction: Double) -> String {
  switch fraction {
  case ..<0.25: return "░"
  case ..<0.5: return "▒"
  case ..<0.75: return "▓"
  default: return "█"
  }
}

func heatStripGlyph(
  value: Double,
  maximumValue: Double
) -> String {
  guard maximumValue > 0 else {
    return " "
  }

  let fraction = min(max(abs(value) / maximumValue, 0), 1)
  if fraction == 0 {
    return " "
  }
  return intensityRampGlyph(fraction: fraction)
}

@MainActor
@ViewBuilder
func heatStripBody(
  entries: [BarChartEntry],
  maximumValue: Double,
  cellWidth: Int
) -> some View {
  let effectiveWidth = max(1, cellWidth)

  VStack(alignment: .leading, spacing: 0) {
    HStack(alignment: .center, spacing: 1) {
      ForEach(entries.indices, id: \.self) { index in
        let accentStyle =
          entries[index].tone == .automatic
          ? AnyShapeStyle(.tint)
          : metricAccentStyle(for: entries[index].tone)
        let glyph = heatStripGlyph(
          value: entries[index].value,
          maximumValue: maximumValue
        )

        Text(String(repeating: glyph, count: effectiveWidth))
          .foregroundStyle(accentStyle)
          .frame(width: effectiveWidth, height: 1, alignment: .center)
      }
    }
    HStack(alignment: .center, spacing: 1) {
      ForEach(entries.indices, id: \.self) { index in
        Text(String(entries[index].label.prefix(effectiveWidth)))
          .lineLimit(1)
          .foregroundStyle(.foreground)
          .frame(width: effectiveWidth, height: 1, alignment: .center)
      }
    }
  }
}

@MainActor
@ViewBuilder
func barChartRow(
  _ entry: BarChartEntry,
  maximumValue: Double,
  barWidth: Int,
  labelWidth: Int
) -> some View {
  let track = metricTrackString(
    fraction: maximumValue > 0 ? min(max(abs(entry.value) / maximumValue, 0), 1) : 0,
    barWidth: barWidth
  )
  let accentStyle =
    entry.tone == .automatic
    ? AnyShapeStyle(.tint)
    : metricAccentStyle(for: entry.tone)

  HStack(alignment: .center, spacing: 1) {
    Text(entry.label)
      .lineLimit(1)
      .truncationMode(.tail)
      .foregroundStyle(.foreground)
      .frame(width: max(1, labelWidth), height: 1, alignment: .leading)
    HStack(alignment: .center, spacing: 0) {
      Text(track.filled)
        .foregroundStyle(accentStyle)
      Text(track.empty)
        .foregroundStyle(.separator)
    }
    Text(metricValueString(entry.value))
      .foregroundStyle(.separator)
  }
}
