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

/// One rasterized cell in a line chart plot grid.
struct LineRasterCell: Equatable, Sendable {
  /// `•` for isolated points, `│`/`─`/`╭`/`╮`/`╰`/`╯` for connector
  /// segments. Picked by `connectorGlyph(at:neighbor:)`.
  var glyph: Character
}

/// Maps a series of `(x, y)` points (already sorted by x) into a
/// `plotHeight × plotWidth` grid. `nil` cells stay empty.
func rasterizeLine(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int
) -> [[LineRasterCell?]] {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  guard !points.isEmpty else { return grid }

  if points.count == 1 {
    let p = points[0]
    let col = xCell(value: p.x, domain: domain.x, plotWidth: width)
    let row = yCell(value: p.y, domain: domain.y, plotHeight: height)
    grid[row][col] = LineRasterCell(glyph: "•")
    return grid
  }

  // Compute (col, row) for every input point first.
  let cells: [(col: Int, row: Int)] = points.map { p in
    (xCell(value: p.x, domain: domain.x, plotWidth: width),
     yCell(value: p.y, domain: domain.y, plotHeight: height))
  }

  // For each consecutive pair, fill the vertical span between them at
  // each column they cover, then place a connector glyph.
  for i in 0..<(cells.count - 1) {
    let from = cells[i]
    let to   = cells[i + 1]
    let colStart = min(from.col, to.col)
    let colEnd   = max(from.col, to.col)
    let rowStart = min(from.row, to.row)
    let rowEnd   = max(from.row, to.row)

    // Vertical fill in the leading column (from current Y down to the
    // midpoint), and in the trailing column (from the midpoint up to
    // the next Y). Concretely, fill every row between rowStart and
    // rowEnd in the column closer to that endpoint.
    for row in rowStart...rowEnd {
      let col = (row <= (rowStart + rowEnd) / 2) ? (from.row <= to.row ? from.col : to.col)
                                                 : (from.row <= to.row ? to.col   : from.col)
      if grid[row][col] == nil {
        grid[row][col] = LineRasterCell(glyph: "│")
      }
    }

    // Horizontal fill between columns at the latched-in Y.
    if colStart != colEnd {
      let rowAtFrom = from.row
      let rowAtTo   = to.row
      for col in (colStart + 1)..<colEnd {
        let row = col < (colStart + colEnd) / 2 ? rowAtFrom : rowAtTo
        if grid[row][col] == nil {
          grid[row][col] = LineRasterCell(glyph: "─")
        }
      }
    }

    // Corner glyphs at the endpoints.
    grid[from.row][from.col] = LineRasterCell(glyph: connectorGlyph(at: from, neighbor: to))
    grid[to.row][to.col]     = LineRasterCell(glyph: connectorGlyph(at: to, neighbor: from))
  }

  return grid
}

private func connectorGlyph(
  at cell: (col: Int, row: Int),
  neighbor: (col: Int, row: Int)
) -> Character {
  // Same row → horizontal segment.
  if cell.row == neighbor.row { return "─" }
  // Same column → vertical segment.
  if cell.col == neighbor.col { return "│" }

  let goingRight = neighbor.col > cell.col
  let goingDown  = neighbor.row > cell.row
  switch (goingRight, goingDown) {
  case (true,  true):  return "╮"   // turn down to the right
  case (true,  false): return "╯"   // turn up to the right
  case (false, true):  return "╭"   // turn down to the left
  case (false, false): return "╰"   // turn up to the left
  }
}

/// Renders `.area` style: fills every cell between the line and
/// `baselineRow` with `▒`, then the line itself on top.
func rasterizeArea(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int,
  baselineRow: Int
) -> [[LineRasterCell?]] {
  let lineGrid = rasterizeLine(
    points: points,
    domain: domain,
    plotWidth: plotWidth,
    plotHeight: plotHeight
  )
  var grid = lineGrid
  let height = max(1, plotHeight)
  let width  = max(1, plotWidth)
  let clampedBaseline = min(max(baselineRow, 0), height - 1)

  // For each column, find the topmost filled row from the line raster.
  // Fill from that row + 1 down to `clampedBaseline` with `▒`.
  for col in 0..<width {
    var topRow: Int?
    for row in 0..<height where lineGrid[row][col] != nil {
      topRow = row
      break
    }
    guard let topRow else { continue }
    let fillStart = topRow + 1
    let fillEnd = clampedBaseline
    guard fillStart <= fillEnd else { continue }
    for row in fillStart...fillEnd where grid[row][col] == nil {
      grid[row][col] = LineRasterCell(glyph: "▒")
    }
  }
  return grid
}

/// Renders `.step` style: a horizontal segment at each sample's Y for
/// the full width up to (but not including) the next sample's column,
/// then a vertical jump in that column to the new Y.
func rasterizeStep(
  points: [LineChartPoint],
  domain: LineChartDomain,
  plotWidth: Int,
  plotHeight: Int
) -> [[LineRasterCell?]] {
  let width = max(1, plotWidth)
  let height = max(1, plotHeight)
  var grid: [[LineRasterCell?]] = Array(
    repeating: Array(repeating: nil, count: width),
    count: height
  )

  guard !points.isEmpty else { return grid }

  let cells: [(col: Int, row: Int)] = points.map { p in
    (xCell(value: p.x, domain: domain.x, plotWidth: width),
     yCell(value: p.y, domain: domain.y, plotHeight: height))
  }

  for i in 0..<cells.count {
    let here = cells[i]
    let endCol = (i + 1 < cells.count) ? cells[i + 1].col : width
    // Horizontal hold from `here.col` to `endCol - 1` at `here.row`.
    for col in here.col..<min(endCol, width) where grid[here.row][col] == nil {
      grid[here.row][col] = LineRasterCell(glyph: "─")
    }
    // Vertical jump in `endCol` from `here.row` to the next sample's
    // row, if there is one.
    if i + 1 < cells.count, endCol < width {
      let next = cells[i + 1]
      let rowStart = min(here.row, next.row)
      let rowEnd   = max(here.row, next.row)
      for row in rowStart...rowEnd where grid[row][endCol] == nil {
        grid[row][endCol] = LineRasterCell(glyph: "│")
      }
    }
  }
  return grid
}
