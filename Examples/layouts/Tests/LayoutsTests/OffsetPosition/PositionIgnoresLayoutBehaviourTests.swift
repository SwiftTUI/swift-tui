import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PositionIgnoresLayoutBehaviourTests {
  /// `.position(x: 40, y: 14)` CENTERS the child at the given point
  /// in the wrapper's coordinate space.  On an 80×28 surface with the
  /// header consuming row 0, the ZStack itself spans rows 1..27 — but
  /// `.position` is expressed in the wrapper's own coordinate space
  /// (the ZStack's origin is local `(0, 0)`), so the child sits at
  /// row 14 of the ZStack.  The 5-cell `[PIN]` centered at column 40
  /// lands with its leading column at 38 (40 − 5/2).
  ///
  /// We pin row = 14 within the ZStack (± 1 for rounding) and the
  /// center column ≈ 40 (± 1) within the `[PIN]` span.
  @Test("position centers the child at the given absolute point")
  func positionAnchorsAtAbsolutePoint() {
    let raster = render(
      PositionIgnoresLayout(),
      width: 80,
      height: 28
    ).rasterSurface

    let joined = raster.lines.joined(separator: "\n")

    guard let pinRow = raster.firstRow(containing: "[PIN]"),
      let pinLine = raster.row(at: pinRow),
      let pinCol = column(of: "[PIN]", in: pinLine)
    else {
      Issue.record("expected `[PIN]` in raster\n\(joined)")
      return
    }

    // The header `"Position ignores layout"` occupies row 0; the
    // ZStack starts at row 1.  A `.position(y: 14)` within that
    // ZStack centers the `[PIN]` line at raster row 15 (= 1 + 14).
    let expectedRow = 1 + 14
    #expect(
      abs(pinRow - expectedRow) <= 1,
      "expected [PIN] on row \(expectedRow) ± 1, got \(pinRow)\n\(joined)"
    )

    // `[PIN]` is 5 cells wide.  Centered at column 40 means the
    // leading column sits at 40 − 5/2 = 38 (integer division).
    // The center cell therefore covers columns 38..42; the midpoint
    // column is `pinCol + 2`.
    let centerCol = pinCol + 2
    #expect(
      abs(centerCol - 40) <= 1,
      "expected [PIN] centered at col 40 ± 1, got center=\(centerCol) (leading=\(pinCol))\n\(joined)"
    )
  }
}
