import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct HorizontalScrollWithInfiniteChildBehaviourTests {
  /// Observed raster at 40×20:
  ///
  /// ```
  /// [0] ||
  /// [1] | Horizontal scroll with infinite child|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|   <- top border (width 22)
  /// [3] | ▌item 0 item 1 item 2▐|
  /// [4] | ▌████████████━━━━━━━▶▐|   <- horizontal scroll indicator
  /// [5] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|   <- bottom border
  /// ```
  ///
  /// Two invariants pinned together:
  ///   - Rendering completes (the test returning at all proves there
  ///     is no infinite-loop in greedy-child measurement).
  ///   - `item 0` is painted somewhere in the raster.
  ///   - The bordered viewport is exactly 22 cells wide (20 frame +
  ///     2 border edges), proving the ScrollView took the finite
  ///     horizontal proposal and the greedy `.frame(maxWidth: .infinity)`
  ///     children collapsed to their natural widths instead of
  ///     exploding the content width.
  @Test(
    "horizontal ScrollView with .infinity child renders at the finite proposed width"
  )
  func horizontalScrollBoundsInfiniteChild() {
    let raster = render(
      HorizontalScrollWithInfiniteChild(),
      width: 40,
      height: 20
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      raster.firstRow(containing: "item 0") != nil,
      "expected `item 0` somewhere in the raster\n\(joined)"
    )

    // Border rows: find the bordered region's top edge, then measure
    // its width from the first to last non-space cell.
    let topCorners: Set<Character> = ["▛", "┌", "┏", "╭"]
    var topRow: Int? = nil
    for row in 0..<raster.cells.count {
      let line = raster.cells[row]
      if line.contains(where: { topCorners.contains($0.character) }) {
        topRow = row
        break
      }
    }

    guard let topRow else {
      Issue.record("expected top-border corner glyph (top edge of viewport)\n\(joined)")
      return
    }
    let topCells = raster.cells[topRow]
    let leftEdge = topCells.firstIndex { $0.character != " " } ?? 0
    let rightEdge = topCells.lastIndex { $0.character != " " } ?? 0
    let borderWidth = rightEdge - leftEdge + 1

    #expect(
      borderWidth == 22,
      """
      expected bordered viewport width of 22 cells (20-cell frame + \
      2 border edges); got \(borderWidth) (topRow=\(topRow), \
      leftEdge=\(leftEdge), rightEdge=\(rightEdge)). Width != 22 \
      would mean the `.infinity` child demanded more (or less) than \
      its natural width.
      \(joined)
      """
    )
  }
}
