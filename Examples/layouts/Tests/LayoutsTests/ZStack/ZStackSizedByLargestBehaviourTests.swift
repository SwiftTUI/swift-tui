import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ZStackSizedByLargestBehaviourTests {
  /// A `ZStack` containing a tiny `Text("·").frame(width: 3, height: 1)`
  /// and a `Rectangle().fill(Color.gray).frame(width: 30, height: 10)`
  /// must report a size equal to the LARGER child along each axis —
  /// i.e. `30 × 10`, not `3 × 1`.
  ///
  /// Pinned via the raster: the gray-filled cells (the `Rectangle`'s
  /// painted region) must span exactly 10 contiguous rows of 30
  /// contiguous columns each. If the ZStack had clamped to the small
  /// `Text("·")` child, only a 3×1 patch of cells would carry the
  /// gray fill (the rest would be clipped to the smaller container).
  @Test("ZStack measures and paints at the largest child's size")
  func stackGrowsToLargestChild() {
    let raster = render(
      ZStackSizedByLargest(),
      width: 60,
      height: 20
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    var grayByRow: [Int: [Int]] = [:]
    for (row, cells) in raster.cells.enumerated() {
      for (col, cell) in cells.enumerated() where cell.style?.backgroundColor == Color.gray {
        grayByRow[row, default: []].append(col)
      }
    }

    let grayRows = grayByRow.keys.sorted()
    #expect(
      grayRows.count == 10,
      """
      expected 10 rows of gray-filled cells (Rectangle is 30×10); \
      got \(grayRows.count) rows
      \(joined)
      """
    )

    // Rows must be contiguous (no gaps).
    if let first = grayRows.first, let last = grayRows.last {
      #expect(
        last - first == grayRows.count - 1,
        "expected gray rows to be contiguous; got rows=\(grayRows)\n\(joined)"
      )
    }

    // Each gray row must have exactly 30 contiguous gray cells.
    for row in grayRows {
      let cols = grayByRow[row]?.sorted() ?? []
      #expect(
        cols.count == 30,
        "row \(row) should have 30 gray cells; got \(cols.count)\n\(joined)"
      )
      if let first = cols.first, let last = cols.last {
        #expect(
          last - first == cols.count - 1,
          "row \(row) gray cells should be contiguous; got cols=\(cols)\n\(joined)"
        )
      }
    }
  }
}
