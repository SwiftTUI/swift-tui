struct ComposedSeriesGrid: Equatable, Sendable {
  /// Rasterized cells across all series, with later series overwriting
  /// earlier ones (after area fills are painted first).
  var grid: [[LineRasterCell?]]
  /// Index into `series` for the series that owns each filled cell; the
  /// view layer uses this to pick the tone.
  var seriesIndex: [[Int?]]
}

/// Composites every series in z-order: areas first across all `.area`
/// series, then lines and steps (and the area's own line) on top in
/// declaration order. Later series win when cells collide.
func composeSeriesGrids(
  series: [LineChartSeries],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int,
  baselineRow: Int
) -> ComposedSeriesGrid {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )
  var seriesIndex: [[Int?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  for (index, s) in series.enumerated() where s.style == .area {
    let g = rasterizeArea(
      points: s.points, domain: domain,
      plotWidth: width, plotHeight: height,
      baselineRow: baselineRow
    )
    for row in 0..<height {
      for col in 0..<width where g[row][col] != nil {
        grid[row][col] = g[row][col]
        seriesIndex[row][col] = index
      }
    }
  }

  for (index, s) in series.enumerated() {
    let g: [[LineRasterCell?]]
    switch s.style {
    case .line, .area:
      g = rasterizeLine(
        points: s.points, domain: domain,
        plotWidth: width, plotHeight: height
      )
    case .step:
      g = rasterizeStep(
        points: s.points, domain: domain,
        plotWidth: width, plotHeight: height
      )
    }
    for row in 0..<height {
      for col in 0..<width where g[row][col] != nil {
        grid[row][col] = g[row][col]
        seriesIndex[row][col] = index
      }
    }
  }

  return ComposedSeriesGrid(grid: grid, seriesIndex: seriesIndex)
}
