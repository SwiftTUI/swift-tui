import SwiftTUIViews

// Bullet-chart helpers: the target summary string and the segmented track
// renderer that marks the target position with a diamond glyph.
//
// Split out of `ChartSupport.swift` so that file is not a catch-all for every
// chart family.

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
