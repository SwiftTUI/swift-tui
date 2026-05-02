import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ZStackPaintOrderOverlapBehaviourTests {
  /// Two same-size `Rectangle`s overlap on a shared 10×4 region.  The
  /// red fill is declared first and the blue fill second, so the later
  /// (blue) child paints OVER the earlier (red) child at every cell
  /// inside the shared box.
  ///
  /// Sampling a cell inside the overlap proves the paint-order rule:
  /// its `style?.backgroundColor` is `Color.blue` (not `Color.red`).
  @Test("later child wins at shared cells in a ZStack")
  func laterChildPaintsOverEarlier() {
    let raster = render(
      ZStackPaintOrderOverlap(),
      width: 40,
      height: 10
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // Locate a cell with a gray/red/blue background inside the 10×4
    // overlap region.  The outer `.padding(1)` + header row ("ZStack
    // paint order overlap") sit above the rectangles, so the shared
    // region is some rows below the top of the raster.  We walk the
    // raster looking for the first row with `Color.blue` cells.
    var blueCells: [(row: Int, col: Int)] = []
    var redCells: [(row: Int, col: Int)] = []
    for (row, line) in raster.cells.enumerated() {
      for (col, cell) in line.enumerated() {
        if cell.style?.backgroundColor == Color.blue {
          blueCells.append((row, col))
        } else if cell.style?.backgroundColor == Color.red {
          redCells.append((row, col))
        }
      }
    }

    #expect(
      !blueCells.isEmpty,
      "expected at least one Color.blue-backed cell from the later Rectangle\n\(joined)"
    )
    #expect(
      redCells.isEmpty,
      """
      expected NO Color.red-backed cells — the later blue child must fully \
      cover the earlier red child across the shared 10×4 frame; \
      got \(redCells.count) red cells
      \(joined)
      """
    )

    // Contiguous 10×4 blue region — paint covered the whole shared box.
    let blueRows = Set(blueCells.map(\.row))
    #expect(
      blueRows.count == 4,
      "expected 4 rows of blue cells (10×4 frame); got \(blueRows.count)\n\(joined)"
    )

    // Every blue row should have 10 contiguous blue cells.
    for row in blueRows {
      let cellsOnRow = blueCells.filter { $0.row == row }.map(\.col).sorted()
      #expect(
        cellsOnRow.count == 10,
        "row \(row) should have 10 blue cells; got \(cellsOnRow.count)\n\(joined)"
      )
    }
  }
}
