import SwiftTUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct VerticalScrollMeasuresContentBehaviourTests {
  /// Observed raster at 40×20:
  ///
  /// ```
  /// [0] ||
  /// [1] | Vertical scroll measures content|
  /// [2] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|   <- top border
  /// [3] | ▌row 0                              █▐|
  /// [4] | ▌row 1                              █▐|
  /// [5] | ▌row 2                              █▐|
  /// [6] | ▌row 3                              ┃▐|
  /// [7] | ▌row 4                              ┃▐|
  /// [8] | ▌row 5                              ┃▐|
  /// [9] | ▌row 6                              ┃▐|
  /// [10]| ▌row 7                              ▼▐|
  /// [11]| ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|   <- bottom border
  /// ```
  ///
  /// Three invariants pinned together:
  ///   - `row 0` is painted inside the viewport (first content row
  ///     of the bordered region).
  ///   - `row 29` does NOT appear — the 30-row content cannot fit in
  ///     the 8-row viewport, so the tail is scrolled off.
  ///   - The bordered region spans exactly 10 rows (8 frame rows plus
  ///     the two border edges), proving the ScrollView honoured the
  ///     `.frame(height: 8)` proposal instead of growing to fit its
  ///     content.
  @Test("viewport clips content to .frame(height: 8); row 0 visible, row 29 scrolled off")
  func viewportClipsAndMeasuresFromProposal() {
    let raster = render(VerticalScrollMeasuresContent(), width: 40, height: 20).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    #expect(
      raster.firstRow(containing: "row 0") != nil,
      "expected `row 0` inside viewport\n\(joined)"
    )
    #expect(
      raster.firstRow(containing: "row 29") == nil,
      "expected `row 29` NOT present (content overflows 8-row viewport)\n\(joined)"
    )

    // Border rows: `.border(.separator)` paints half-block corner
    // glyphs (`▛ ▜ ▙ ▟`) around the `.frame(height: 8)` region. The
    // bordered region should span exactly 10 rows (8 content + 2
    // border edges).
    let topCorners: Set<Character> = ["▛", "┌", "┏", "╭"]
    let bottomCorners: Set<Character> = ["▙", "└", "┗", "╰"]
    var topRow: Int? = nil
    var bottomRow: Int? = nil
    for row in 0..<raster.cells.count {
      let line = raster.cells[row]
      if topRow == nil, line.contains(where: { topCorners.contains($0.character) }) {
        topRow = row
      }
      if line.contains(where: { bottomCorners.contains($0.character) }) {
        bottomRow = row
      }
    }

    guard let topRow, let bottomRow else {
      Issue.record("expected top + bottom border corner glyphs\n\(joined)")
      return
    }
    let borderHeight = bottomRow - topRow + 1
    #expect(
      borderHeight == 10,
      """
      expected bordered region to be 10 rows tall (8-row frame + 2 \
      border edges); got \(borderHeight) (topRow=\(topRow), bottomRow=\(bottomRow))
      \(joined)
      """
    )
  }
}
