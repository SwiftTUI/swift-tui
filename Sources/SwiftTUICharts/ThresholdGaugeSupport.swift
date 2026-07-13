import SwiftTUIViews

// Threshold-gauge helpers: band normalization/sorting, per-value band tone
// lookup, and the gauge track renderer that colors each segment by the band
// its mid-point value falls into.
//
// Split out of `ChartSupport.swift` so that file is not a catch-all for every
// chart family.

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
