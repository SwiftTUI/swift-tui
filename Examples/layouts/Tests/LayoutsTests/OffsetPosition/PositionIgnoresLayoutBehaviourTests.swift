import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct PositionIgnoresLayoutBehaviourTests {
  /// `.position(x: 60, y: 5)` CENTERS the child at the given point in
  /// the wrapper's (ZStack's) coordinate space.  On an 80×28 surface
  /// the header `"Position ignores layout"` consumes row 0, so the
  /// ZStack starts at raster row 1.  A `.position(y: 5)` within that
  /// ZStack therefore lands `[PIN]` on raster row 6 (= 1 + 5).  The
  /// 5-cell `[PIN]` centered at column 60 has its leading column at
  /// 60 − 5/2 = 58 and its center cell at column 60.
  ///
  /// Anchor `(60, 5)` is chosen to be OFF-CENTER for the ZStack so
  /// removing `.position` produces a visibly different raster (see
  /// `positionIsNonVacuous` below).
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

    // Header occupies row 0; ZStack starts at row 1.  `.position(y: 5)`
    // within the ZStack places `[PIN]` at raster row 6 (= 1 + 5).
    let expectedRow = 1 + 5
    #expect(
      abs(pinRow - expectedRow) <= 1,
      "expected [PIN] on row \(expectedRow) ± 1, got \(pinRow)\n\(joined)"
    )

    // `[PIN]` is 5 cells wide.  Centered at column 60 means the
    // leading column sits at 60 − 5/2 = 58 (integer division).
    // The center cell therefore covers columns 58..62; the midpoint
    // column is `pinCol + 2`.
    let centerCol = pinCol + 2
    #expect(
      abs(centerCol - 60) <= 1,
      "expected [PIN] centered at col 60 ± 1, got center=\(centerCol) (leading=\(pinCol))\n\(joined)"
    )
  }

  /// Non-vacuity check: render the positioned layout alongside a
  /// variant without `.position`.  The `[PIN]` text must land on a
  /// different row or column in the two rasters — otherwise the
  /// modifier would be a no-op and the primary assertion above would
  /// be a false green.
  @Test("removing .position visibly changes the raster (proves the modifier works)")
  func positionIsNonVacuous() {
    let withPosition = render(
      PositionIgnoresLayout(),
      width: 80,
      height: 28,
      id: "with-position"
    ).rasterSurface
    let withoutPosition = render(
      WithoutPositionVariant(),
      width: 80,
      height: 28,
      id: "without-position"
    ).rasterSurface

    let withDump = withPosition.lines.joined(separator: "\n")
    let withoutDump = withoutPosition.lines.joined(separator: "\n")

    guard let rowWith = withPosition.firstRow(containing: "[PIN]"),
      let lineWith = withPosition.row(at: rowWith),
      let colWith = column(of: "[PIN]", in: lineWith)
    else {
      Issue.record("WITH-position variant: missing [PIN]\nWITH:\n\(withDump)")
      return
    }

    guard let rowWithout = withoutPosition.firstRow(containing: "[PIN]"),
      let lineWithout = withoutPosition.row(at: rowWithout),
      let colWithout = column(of: "[PIN]", in: lineWithout)
    else {
      Issue.record("WITHOUT-position variant: missing [PIN]\nWITHOUT:\n\(withoutDump)")
      return
    }

    #expect(
      rowWith != rowWithout || colWith != colWithout,
      """
      expected with/without .position to paint [PIN] at different row/col; \
      got with=(\(rowWith),\(colWith)) without=(\(rowWithout),\(colWithout))
      WITH:
      \(withDump)
      WITHOUT:
      \(withoutDump)
      """
    )
  }
}

/// Identical to `PositionIgnoresLayout` except `[PIN]` carries no
/// `.position(x:y:)` modifier.  Used by the A/B non-vacuity assertion.
private struct WithoutPositionVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Position ignores layout").foregroundStyle(.muted)
      ZStack {
        Rectangle().fill(Color.blue)
        Text("[PIN]")
      }
    }
  }
}
