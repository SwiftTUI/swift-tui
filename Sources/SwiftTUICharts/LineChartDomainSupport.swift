import SwiftTUICore

struct LineChartDomain: Equatable, Sendable {
  var x: ClosedRange<Double>
  var y: ClosedRange<Double>
}

/// Computes the combined X/Y range across all series. Returns `nil` when
/// no series contains points.
func plotDomain(series: [LineChartSeries]) -> LineChartDomain? {
  var minX = Double.infinity
  var maxX = -Double.infinity
  var minY = Double.infinity
  var maxY = -Double.infinity
  var any = false
  for s in series {
    for p in s.points {
      any = true
      if p.x < minX { minX = p.x }
      if p.x > maxX { maxX = p.x }
      if p.y < minY { minY = p.y }
      if p.y > maxY { maxY = p.y }
    }
  }
  guard any else { return nil }
  return LineChartDomain(x: minX...maxX, y: minY...maxY)
}

/// Maps a domain X value to a column index in `[0, plotWidth)`.
func xCell(value: Double, domain: ClosedRange<Double>, plotWidth: Int) -> Int {
  let span = domain.upperBound - domain.lowerBound
  guard span > 0, plotWidth > 0 else { return 0 }
  let fraction = (value - domain.lowerBound) / span
  let column = Int((fraction * Double(plotWidth - 1)).rounded())
  return min(max(column, 0), plotWidth - 1)
}

/// Maps a domain Y value to a row index in `[0, plotHeight)`, inverted
/// so row 0 corresponds to the top of the plot.
func yCell(value: Double, domain: ClosedRange<Double>, plotHeight: Int) -> Int {
  let span = domain.upperBound - domain.lowerBound
  guard span > 0, plotHeight > 0 else { return 0 }
  let fraction = (value - domain.lowerBound) / span
  let invertedFraction = 1 - fraction
  let row = Int((invertedFraction * Double(plotHeight - 1)).rounded())
  return min(max(row, 0), plotHeight - 1)
}
