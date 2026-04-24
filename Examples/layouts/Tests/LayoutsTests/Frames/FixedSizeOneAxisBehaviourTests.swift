import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct FixedSizeOneAxisBehaviourTests {
  /// `.fixedSize(horizontal: false, vertical: true)` on a Text asks
  /// it to honour the parent's width proposal (so wrapping still
  /// happens) while taking its intrinsic height. Wrapping a long
  /// string inside an 8-wide frame therefore yields at least two
  /// rows containing fragments of the text.
  @Test("text wraps across multiple rows inside an 8-wide frame")
  func textWrapsAcrossRows() {
    let raster = render(FixedSizeOneAxis(), width: 40, height: 20).rasterSurface

    // Words that must each appear somewhere in the raster.
    let words = ["abc", "def", "ghi", "jkl", "mno", "pqr"]

    let rowsContainingAWord = (0..<raster.lines.count).filter { rowIdx in
      guard let line = raster.row(at: rowIdx) else { return false }
      return words.contains { line.contains($0) }
    }

    #expect(
      rowsContainingAWord.count >= 2,
      "expected wrap across >=2 rows; observed row indices: \(rowsContainingAWord)\n\(raster.lines.joined(separator: "\n"))"
    )
  }
}
