import Foundation

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
