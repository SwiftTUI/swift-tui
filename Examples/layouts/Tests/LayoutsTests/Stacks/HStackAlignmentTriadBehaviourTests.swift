import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct HStackAlignmentTriadBehaviourTests {
  /// The triad renders three HStacks stacked vertically, each with
  /// mixed-height children (`tall`: 3 content lines + border ⇒ 5 rows;
  /// `short`: 1 content line + border ⇒ 3 rows). The HStack's height
  /// is dictated by `tall` (5 rows). `short`'s single content row
  /// lands at a different absolute y depending on the HStack's
  /// vertical alignment:
  ///
  ///   .top    → short's content row == tall's FIRST content row
  ///   .center → short's content row == tall's MIDDLE content row
  ///   .bottom → short's content row == tall's LAST content row
  ///
  /// The three `tall` children produce 9 `"tall"` text rows in the
  /// raster (3 HStacks × 3 lines each), in three consecutive
  /// triplets. The three `short` children produce 3 `"short"` rows,
  /// one per HStack.
  @Test("Short child anchors per vertical alignment")
  func shortChildAnchorsPerAlignment() {
    let raster = render(HStackAlignmentTriad(), width: 40, height: 25).rasterSurface
    let shortRows = raster.rows(containing: "short")
    let tallRows = raster.rows(containing: "tall")

    #expect(
      shortRows.count == 3,
      "three HStacks each render one 'short' row; got \(shortRows.count)"
    )
    #expect(
      tallRows.count == 9,
      "three HStacks × 3 'tall' lines each = 9; got \(tallRows.count)"
    )

    guard shortRows.count == 3, tallRows.count == 9 else { return }

    // Split tall rows into three contiguous triplets (one per HStack).
    let triplets: [[Int]] = stride(from: 0, to: 9, by: 3).map { Array(tallRows[$0..<$0 + 3]) }
    let (topTall, centerTall, bottomTall) = (triplets[0], triplets[1], triplets[2])

    #expect(
      shortRows[0] == topTall.first,
      ".top: short's row (\(shortRows[0])) should equal tall's first row (\(topTall.first!))"
    )
    #expect(
      shortRows[1] == centerTall[1],
      ".center: short's row (\(shortRows[1])) should equal tall's middle row (\(centerTall[1]))"
    )
    #expect(
      shortRows[2] == bottomTall.last,
      ".bottom: short's row (\(shortRows[2])) should equal tall's last row (\(bottomTall.last!))"
    )
  }
}
