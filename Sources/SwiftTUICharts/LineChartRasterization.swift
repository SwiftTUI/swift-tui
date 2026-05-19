/// One rasterized cell in a line chart plot grid.
struct LineRasterCell: Equatable, Sendable {
  /// `•` for isolated points, `│`/`─`/`╭`/`╮`/`╰`/`╯` for connector
  /// segments. Picked by `dataPointGlyph(...)` / `elbowGlyph(...)`.
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

  let cells: [(col: Int, row: Int)] = points.map { p in
    (
      xCell(value: p.x, domain: domain.x, plotWidth: width),
      yCell(value: p.y, domain: domain.y, plotHeight: height)
    )
  }

  for i in 0..<(cells.count - 1) {
    drawSegment(from: cells[i], to: cells[i + 1], into: &grid)
  }

  for i in 0..<cells.count {
    let previous = i > 0 ? cells[i - 1] : nil
    let next = i + 1 < cells.count ? cells[i + 1] : nil
    grid[cells[i].row][cells[i].col] = LineRasterCell(
      glyph: dataPointGlyph(current: cells[i], previous: previous, next: next)
    )
  }

  return grid
}

private func drawSegment(
  from: (col: Int, row: Int),
  to: (col: Int, row: Int),
  into grid: inout [[LineRasterCell?]]
) {
  if from.row == to.row {
    let colStart = min(from.col, to.col)
    let colEnd = max(from.col, to.col)
    for col in colStart...colEnd where grid[from.row][col] == nil {
      grid[from.row][col] = LineRasterCell(glyph: "─")
    }
    return
  }
  if from.col == to.col {
    let rowStart = min(from.row, to.row)
    let rowEnd = max(from.row, to.row)
    for row in rowStart...rowEnd where grid[row][from.col] == nil {
      grid[row][from.col] = LineRasterCell(glyph: "│")
    }
    return
  }

  let goingRight = to.col > from.col
  let goingDown = to.row > from.row

  let hStart = goingRight ? from.col + 1 : to.col
  let hEnd = goingRight ? to.col : from.col - 1
  if hStart <= hEnd {
    for col in hStart...hEnd where grid[from.row][col] == nil {
      grid[from.row][col] = LineRasterCell(
        glyph: col == to.col
          ? elbowGlyph(goingRight: goingRight, goingDown: goingDown)
          : "─"
      )
    }
  }

  let vStart = min(from.row, to.row) + 1
  let vEnd = max(from.row, to.row) - 1
  if vStart <= vEnd {
    for row in vStart...vEnd where grid[row][to.col] == nil {
      grid[row][to.col] = LineRasterCell(glyph: "│")
    }
  }
}

private func elbowGlyph(goingRight: Bool, goingDown: Bool) -> Character {
  switch (goingRight, goingDown) {
  case (true, true): "╮"
  case (true, false): "╯"
  case (false, true): "╭"
  case (false, false): "╰"
  }
}

private func dataPointGlyph(
  current: (col: Int, row: Int),
  previous: (col: Int, row: Int)?,
  next: (col: Int, row: Int)?
) -> Character {
  guard previous != nil || next != nil else { return "•" }

  if previous == nil, let next {
    if next.row == current.row { return "─" }
    return next.row > current.row ? "╭" : "╰"
  }

  if let previous, next == nil {
    if previous.row == current.row { return "─" }
    return previous.row > current.row ? "╯" : "╮"
  }

  guard let previous, let next else { return "•" }

  let exitRight = next.col > current.col
  if previous.row == current.row {
    return "─"
  }
  let comeFromAbove = previous.row < current.row
  switch (exitRight, comeFromAbove) {
  case (true, true): return "╰"
  case (true, false): return "╭"
  case (false, true): return "╯"
  case (false, false): return "╮"
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
  let width = max(1, plotWidth)
  let clampedBaseline = min(max(baselineRow, 0), height - 1)

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
    (
      xCell(value: p.x, domain: domain.x, plotWidth: width),
      yCell(value: p.y, domain: domain.y, plotHeight: height)
    )
  }

  for i in 0..<cells.count {
    let here = cells[i]
    let endCol = (i + 1 < cells.count) ? cells[i + 1].col : width
    for col in here.col..<min(endCol, width) where grid[here.row][col] == nil {
      grid[here.row][col] = LineRasterCell(glyph: "─")
    }
    if i + 1 < cells.count, endCol < width {
      let next = cells[i + 1]
      let rowStart = min(here.row, next.row)
      let rowEnd = max(here.row, next.row)
      for row in rowStart...rowEnd where grid[row][endCol] == nil {
        grid[row][endCol] = LineRasterCell(glyph: "│")
      }
    }
  }
  return grid
}
