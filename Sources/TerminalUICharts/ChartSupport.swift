import Core
import View

@MainActor
func isEmptyView<V: View>(
  _ view: V
) -> Bool {
  let erased: Any = view
  return erased is EmptyView
}

@MainActor
@ViewBuilder
func chartHeader<Label: View, Summary: View>(
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
func timelineEntryView(
  _ entry: TimelineEntry,
  isLast: Bool
) -> some View {
  let accentStyle = metricAccentStyle(for: entry.tone)

  if let detail = entry.detail {
    HStack(alignment: .top, spacing: 1) {
      VStack(alignment: .leading, spacing: 0) {
        Text(isLast ? "╰" : "├")
          .foregroundStyle(accentStyle)
        Text(isLast ? " " : "│")
          .foregroundStyle(.separator)
      }
      VStack(alignment: .leading, spacing: 0) {
        Text(entry.title)
          .lineLimit(1)
        Text(detail)
          .foregroundStyle(.separator)
          .lineLimit(1)
      }
    }
  } else {
    HStack(alignment: .top, spacing: 1) {
      Text(isLast ? "╰" : "├")
        .foregroundStyle(accentStyle)
      Text(entry.title)
        .lineLimit(1)
    }
  }
}

@MainActor
@ViewBuilder
func legendItemView(
  _ item: LegendItem
) -> some View {
  let accentStyle =
    item.tone == .automatic
    ? AnyShapeStyle(.tint)
    : metricAccentStyle(for: item.tone)

  HStack(alignment: .center, spacing: 1) {
    Text("■")
      .foregroundStyle(accentStyle)
    Text(item.label)
      .foregroundStyle(.foreground)
  }
}

func bulletChartSummaryText(
  target: Double
) -> String {
  "t \(metricValueString(target))"
}

@MainActor
@ViewBuilder
func bulletChartTrackView(
  value: Double,
  target: Double,
  total: Double,
  barWidth: Int,
  accentStyle: AnyShapeStyle
) -> some View {
  let segmentCount = max(1, barWidth)
  let filledCount = min(
    segmentCount,
    max(0, Int((progressFraction(value: value, total: total) * Double(segmentCount)).rounded()))
  )
  let targetIndex = min(
    segmentCount - 1,
    max(
      0,
      Int(
        (progressFraction(value: target, total: total) * Double(max(1, segmentCount - 1))).rounded()
      )
    )
  )

  HStack(alignment: .center, spacing: 0) {
    ForEach(0..<segmentCount, id: \.self) { index in
      if index == targetIndex {
        Text(index < filledCount ? "◆" : "◇")
          .foregroundStyle(.warning)
      } else if index < filledCount {
        Text("█")
          .foregroundStyle(accentStyle)
      } else {
        Text("─")
          .foregroundStyle(.separator)
      }
    }
  }
}

func barChartSummaryText(
  _ entries: [BarChartEntry]
) -> String {
  guard let maximum = entries.map({ abs($0.value) }).max() else {
    return "max 0"
  }

  return "max \(metricValueString(maximum))"
}

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

func stackedBarEffectiveTotal(
  _ entries: [BarChartEntry],
  total: Double?
) -> Double {
  max(1, total ?? entries.reduce(0) { $0 + abs($1.value) })
}

func stackedBarSummaryText(
  _ entries: [BarChartEntry],
  total: Double?
) -> String {
  "sum \(metricValueString(stackedBarEffectiveTotal(entries, total: total)))"
}

func stackedBarWidths(
  entries: [BarChartEntry],
  total: Double,
  barWidth: Int
) -> [Int] {
  let effectiveBarWidth = max(1, barWidth)
  guard !entries.isEmpty else {
    return []
  }

  let weights = entries.map { max(0, abs($0.value)) }
  let totalWeight = weights.reduce(0, +)
  guard totalWeight > 0 else {
    return Array(repeating: 0, count: entries.count)
  }

  var widths = Array(repeating: 0, count: entries.count)
  var remainders: [(index: Int, value: Double)] = []
  var assigned = 0

  for index in entries.indices {
    let rawWidth = (weights[index] / max(total, totalWeight)) * Double(effectiveBarWidth)
    let baseWidth = Int(rawWidth.rounded(.down))
    widths[index] = baseWidth
    assigned += baseWidth
    remainders.append((index, rawWidth - Double(baseWidth)))
  }

  for index in entries.indices
  where weights[index] > 0 && widths[index] == 0 && assigned < effectiveBarWidth {
    widths[index] = 1
    assigned += 1
  }

  if assigned < effectiveBarWidth {
    for remainder in remainders.sorted(by: { $0.value > $1.value })
    where assigned < effectiveBarWidth {
      widths[remainder.index] += 1
      assigned += 1
    }
  } else if assigned > effectiveBarWidth {
    for remainder in remainders.sorted(by: { $0.value < $1.value })
    where assigned > effectiveBarWidth {
      guard widths[remainder.index] > 0 else {
        continue
      }
      widths[remainder.index] -= 1
      assigned -= 1
    }
  }

  return widths
}

@MainActor
@ViewBuilder
func stackedBarTrackView(
  _ entries: [BarChartEntry],
  total: Double,
  barWidth: Int
) -> some View {
  let effectiveBarWidth = max(1, barWidth)
  let widths = stackedBarWidths(
    entries: entries,
    total: total,
    barWidth: effectiveBarWidth
  )
  let assignedWidth = widths.reduce(0, +)

  HStack(alignment: .center, spacing: 0) {
    ForEach(entries.indices, id: \.self) { index in
      let accentStyle =
        entries[index].tone == .automatic
        ? AnyShapeStyle(.tint)
        : metricAccentStyle(for: entries[index].tone)

      if widths[index] > 0 {
        Text(String(repeating: "█", count: widths[index]))
          .foregroundStyle(accentStyle)
      }
    }
    if assignedWidth < effectiveBarWidth {
      Text(String(repeating: "─", count: effectiveBarWidth - assignedWidth))
        .foregroundStyle(.separator)
    }
  }
}

func columnChartSummaryText(
  _ entries: [BarChartEntry]
) -> String {
  barChartSummaryText(entries)
}

func thresholdBandsSorted(
  _ bands: [ThresholdBand],
  total: Double
) -> [ThresholdBand] {
  let clampedTotal = max(1, total)
  if bands.isEmpty {
    return [.init(upTo: clampedTotal, tone: .info)]
  }

  return
    bands
    .map { .init(upTo: min(max($0.upperBound, 0), clampedTotal), tone: $0.tone) }
    .sorted { $0.upperBound < $1.upperBound }
}

func thresholdBandTone(
  for value: Double,
  total: Double,
  bands: [ThresholdBand]
) -> BannerTone {
  let effectiveTotal = max(1, total)
  let clampedValue = min(max(value, 0), effectiveTotal)

  for band in thresholdBandsSorted(bands, total: effectiveTotal)
  where clampedValue <= band.upperBound {
    return band.tone
  }

  return thresholdBandsSorted(bands, total: effectiveTotal).last?.tone ?? .info
}

@MainActor
@ViewBuilder
func thresholdGaugeTrackView(
  value: Double,
  total: Double,
  bands: [ThresholdBand],
  barWidth: Int
) -> some View {
  let segmentCount = max(1, barWidth)
  let effectiveTotal = max(1, total)
  let markerIndex = min(
    segmentCount - 1,
    max(
      0,
      Int(
        (progressFraction(value: value, total: effectiveTotal) * Double(max(1, segmentCount - 1)))
          .rounded())
    )
  )

  HStack(alignment: .center, spacing: 0) {
    ForEach(0..<segmentCount, id: \.self) { index in
      let segmentValue = ((Double(index) + 0.5) / Double(segmentCount)) * effectiveTotal
      let tone = thresholdBandTone(
        for: segmentValue,
        total: effectiveTotal,
        bands: bands
      )
      let accentStyle =
        tone == .automatic
        ? AnyShapeStyle(.tint)
        : metricAccentStyle(for: tone)

      if index == markerIndex {
        Text("◆")
          .foregroundStyle(accentStyle)
      } else {
        Text("━")
          .foregroundStyle(accentStyle)
      }
    }
  }
}

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
  guard maximumValue > 0 else {
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

func heatStripGlyph(
  value: Double,
  maximumValue: Double
) -> String {
  guard maximumValue > 0 else {
    return " "
  }

  let fraction = min(max(abs(value) / maximumValue, 0), 1)
  switch fraction {
  case 0:
    return " "
  case ..<0.25:
    return "░"
  case ..<0.5:
    return "▒"
  case ..<0.75:
    return "▓"
  default:
    return "█"
  }
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
