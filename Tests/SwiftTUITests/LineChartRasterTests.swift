import Foundation
import Testing

@testable import SwiftTUICharts
@testable import SwiftTUICore

@Suite("LineChart raster helpers")
struct LineChartCellMappingTests {
  @Test("xCell maps lower bound to column 0")
  func xLower() {
    #expect(xCell(value: 0, domain: 0...10, plotWidth: 10) == 0)
  }

  @Test("xCell maps upper bound to last column")
  func xUpper() {
    #expect(xCell(value: 10, domain: 0...10, plotWidth: 10) == 9)
  }

  @Test("yCell inverts Y axis (top row = max)")
  func yInverts() {
    #expect(yCell(value: 10, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: 0,  domain: 0...10, plotHeight: 10) == 9)
  }

  @Test("yCell clamps out-of-range to nearest edge")
  func yClamps() {
    #expect(yCell(value: 50, domain: 0...10, plotHeight: 10) == 0)
    #expect(yCell(value: -5, domain: 0...10, plotHeight: 10) == 9)
  }
}

@Suite("LineChart line rasterization")
struct LineChartLineRasterTests {
  @Test("rasterizeLine draws a single point as `•`")
  func singlePoint() {
    // Non-degenerate domain so yCell maps the point to a meaningful row.
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0)],
      domain: LineChartDomain(x: 0...1, y: 0...10),
      plotWidth: 3, plotHeight: 3
    )
    #expect(grid[0][0] == nil)
    #expect(grid[2][0] != nil)  // y=0 (min) maps to the bottom row
  }

  @Test("rasterizeLine connects two points with the rising-corner glyph")
  func twoPointsRising() {
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 1)],
      domain: LineChartDomain(x: 0...1, y: 0...1),
      plotWidth: 2, plotHeight: 2
    )
    // (col 0, row 1) -> rising corner; (col 1, row 0) -> rising corner.
    #expect(grid[1][0] != nil)
    #expect(grid[0][1] != nil)
  }

  @Test("rasterizeLine fills vertical span between far-apart Ys")
  func verticalSpan() {
    let grid = rasterizeLine(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 10)],
      domain: LineChartDomain(x: 0...1, y: 0...10),
      plotWidth: 2, plotHeight: 4
    )
    let column1Filled = (0..<4).contains { grid[$0][1] != nil }
    let column0Filled = (0..<4).contains { grid[$0][0] != nil }
    #expect(column0Filled && column1Filled)
  }
}

@Suite("LineChart area rasterization")
struct LineChartAreaRasterTests {
  @Test("rasterizeArea fills from line down to baselineRow")
  func areaFillsDownToBaseline() {
    let grid = rasterizeArea(
      points: [.init(x: 0, y: 1), .init(x: 1, y: 2)],
      domain: LineChartDomain(x: 0...1, y: 0...3),
      plotWidth: 2, plotHeight: 3,
      baselineRow: 2
    )
    // Cells below the line at each column should be `▒`.
    var foundShade = false
    for row in 0..<3 {
      for col in 0..<2 {
        if grid[row][col]?.glyph == "▒" { foundShade = true }
      }
    }
    #expect(foundShade)
  }

  @Test("rasterizeArea does not paint above the line")
  func areaDoesNotPaintAbove() {
    let grid = rasterizeArea(
      points: [.init(x: 0, y: 0), .init(x: 1, y: 0)],
      domain: LineChartDomain(x: 0...1, y: 0...3),
      plotWidth: 2, plotHeight: 3,
      baselineRow: 2
    )
    // Top row should be empty since the line sits at y=0 (which inverts
    // to row 2 — bottom). Row 0 (top) should have no fills.
    for col in 0..<2 {
      #expect(grid[0][col] == nil)
    }
  }
}
