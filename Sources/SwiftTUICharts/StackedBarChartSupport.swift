import SwiftTUIViews

// Stacked-bar-chart helpers: effective total and summary derivation, the
// largest-remainder width apportionment that distributes a fixed bar width
// across segments, and the stacked track renderer.
//
// Split out of `ChartSupport.swift` so that file is not a catch-all for every
// chart family.

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
