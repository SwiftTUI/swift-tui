import SwiftTUI
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
  /// [2] |     plain above|                  (col 5)
  /// [3] | shifted|                          (col 1)
  /// [4] |     plain below|                  (col 5)
  /// ```
  ///
  /// This matches faithful SwiftUI semantics: increasing an
  /// alignment-guide value shifts the view in the OPPOSITE
  /// direction along the alignment axis. The plan originally
  /// predicted a rightward shift; see
  /// `docs/proposals/layout/BEHAVIOUR_FINDINGS.md` finding #1 — this
  /// test pins the observed (SwiftUI-faithful) behaviour.
  ///
  /// Markers (`"plain above"`, `"shifted"`, `"plain below"`) are
  /// unique words so substring matching is unambiguous — renaming a
  /// single row no longer silently shifts which row this test
  /// measures.
  @Test("shifted row sits 4 cells LEFT of unshifted siblings")
  func shiftedRowOffsetMatchesAlignmentGuide() {
    let raster = render(VStackLeadingGuideShift(), width: 40, height: 10).rasterSurface

    guard
      let plainAbove = raster.firstRow(containing: "plain above"),
      let shifted = raster.firstRow(containing: "shifted"),
      let plainBelow = raster.firstRow(containing: "plain below")
    else {
      let dump = raster.lines.joined(separator: "\n")
      Issue.record(
        "expected 'plain above', 'shifted', and 'plain below' rows in raster:\n\(dump)"
      )
      return
    }

    guard
      let aboveLine = raster.row(at: plainAbove),
      let shiftedLine = raster.row(at: shifted),
      let belowLine = raster.row(at: plainBelow)
    else {
      Issue.record("raster rows missing")
      return
    }

    guard
      let aboveCol = firstNonSpaceCol(in: aboveLine),
      let shiftedCol = firstNonSpaceCol(in: shiftedLine),
      let belowCol = firstNonSpaceCol(in: belowLine)
    else {
      Issue.record("one of the marker rows was entirely whitespace")
      return
    }

    #expect(aboveCol == belowCol, "plain rows share the same leading col")
    // Positive alignment-guide value shifts the view in the opposite
    // direction (SwiftUI-faithful). See
    // docs/proposals/layout/BEHAVIOUR_FINDINGS.md Finding #1.
    #expect(
      shiftedCol == aboveCol - 4,
      "shifted col (\(shiftedCol)) should be 4 less than plain col (\(aboveCol))"
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
