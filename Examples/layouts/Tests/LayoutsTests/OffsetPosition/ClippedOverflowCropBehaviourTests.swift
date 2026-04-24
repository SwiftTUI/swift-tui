import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct ClippedOverflowCropBehaviourTests {
  /// `.clipped()` on a `.frame(width: 8)` crops every cell beyond
  /// column 8 of the modified view's local coordinate space.  The
  /// Text's intrinsic painting (16 `a` cells, enforced by `.fixedSize()`
  /// so the text doesn't truncate itself) is trimmed by the clip so
  /// only 8 `a` cells survive.
  ///
  /// Asserted via the row's raw cell grid (not trimmed `lines`, which
  /// drop trailing whitespace) so columns 8..15 can be inspected
  /// regardless of right-side trimming.
  @Test(".clipped() drops overflowing cells past the frame width")
  func clippedCropsOverflow() {
    let artifacts = render(ClippedOverflowCrop(), width: 80, height: 5)
    let raster = artifacts.rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let aRow = raster.firstRow(containing: "a") else {
      Issue.record("expected a row containing `a` glyphs\n\(joined)")
      return
    }

    let rowCells = raster.cells[aRow]

    // Find the first `a` column — that is the leading column of the
    // frame after the outer `.padding(1)`.
    guard let firstA = rowCells.firstIndex(where: { $0.character == "a" }) else {
      Issue.record("expected at least one `a` on row \(aRow)\n\(joined)")
      return
    }

    // Columns [firstA ..< firstA + 8] are inside the frame: all `a`.
    // Columns [firstA + 8 ..< firstA + 16] are outside the frame: no `a`.
    let insideEnd = firstA + 8
    let outsideEnd = min(firstA + 16, rowCells.count)

    for col in firstA..<min(insideEnd, rowCells.count) {
      #expect(
        rowCells[col].character == "a",
        "expected `a` at col \(col) (inside 8-cell frame); got '\(rowCells[col].character)' on row \(aRow)\n\(joined)"
      )
    }

    for col in insideEnd..<outsideEnd {
      #expect(
        rowCells[col].character != "a",
        "expected no `a` at col \(col) (past 8-cell frame, should be clipped); got `a`\n\(joined)"
      )
    }

    // Sanity: confirm the row has exactly 8 consecutive `a` cells,
    // not 16. This pins the crop width at the frame boundary.
    let aCount = rowCells.reduce(0) { $0 + ($1.character == "a" ? 1 : 0) }
    #expect(
      aCount == 8,
      "expected exactly 8 `a` cells after clip; got \(aCount)\n\(joined)"
    )
  }
}
