import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct VStackLeadingGuideShiftBehaviourTests {
  /// The VStack uses `alignment: .leading` so every child reports
  /// its leading guide and the stack pulls that guide to a common
  /// column. The `shifted` child overrides its `.leading` guide to
  /// the value `4`, which means "the leading anchor sits 4 cells to
  /// the right inside this child." The stack pulls *that* anchor to
  /// the common column, so the child's own leading edge ends up 4
  /// cells to the LEFT of where the unshifted siblings sit.
  ///
  /// Observed raster (40×10 viewport, layout has `.padding(1)`):
  /// ```
  /// [1] |     VStack leading guide shift|   (col 5)
  /// [2] |     normal|                        (col 5)
  /// [3] | shifted|                           (col 1)
  /// [4] |     normal again|                  (col 5)
  /// ```
  ///
  /// This matches faithful SwiftUI semantics: increasing an
  /// alignment-guide value shifts the view in the OPPOSITE
  /// direction along the axis. The plan originally predicted a
  /// rightward shift; see
  /// `docs/proposals/FRAMEWORK_RESERVED_KEY_CONSUMER_ESCAPE_HATCH.md`
  /// finding #1 — this test pins the observed (SwiftUI-faithful)
  /// behaviour.
  @Test("shifted row sits 4 cells LEFT of unshifted siblings")
  func shiftedRowOffsetMatchesAlignmentGuide() {
    let raster = render(VStackLeadingGuideShift(), width: 40, height: 10).rasterSurface

    guard let normalRow = raster.firstRow(containing: "normal"),
      let shiftedRow = raster.firstRow(containing: "shifted")
    else {
      Issue.record(
        "expected 'normal' and 'shifted' rows in raster:\n\(raster.lines.joined(separator: "\n"))"
      )
      return
    }

    let normalCol = firstNonSpaceCol(in: raster.row(at: normalRow) ?? "")
    let shiftedCol = firstNonSpaceCol(in: raster.row(at: shiftedRow) ?? "")

    #expect(normalCol != nil, "row \(normalRow) had no non-space chars")
    #expect(shiftedCol != nil, "row \(shiftedRow) had no non-space chars")

    guard let normalCol, let shiftedCol else { return }

    #expect(
      shiftedCol == normalCol - 4,
      "shifted first-non-space col (\(shiftedCol)) should equal normal (\(normalCol)) - 4"
    )
  }

  /// Returns the 0-based offset of the first non-whitespace character
  /// in `line`, or `nil` if the line is entirely whitespace.
  private func firstNonSpaceCol(in line: String) -> Int? {
    for (offset, char) in line.enumerated() where !char.isWhitespace {
      return offset
    }
    return nil
  }
}
