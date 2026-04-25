import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct GeometryReaderAnchorCornerBehaviourTests {
  /// Reader wrapped in `.frame(width: 40, height: 5).border(.separator)`:
  ///
  /// ```
  /// [1]  Geometry reader anchor corner|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|                                (border ends near col 41)
  /// [3]  ▌                                     [X]▐|
  /// [4]  ▌                                        ▐|
  /// [8]  ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// The tightened proxy width places `[X]` inside the bordered frame
  /// near the top-right corner.
  @Test("[X] anchors inside the tightened 40-wide frame")
  func anchorLandsOutsideFrame() {
    let raster = render(GeometryReaderAnchorCorner(), width: 80, height: 28).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    guard let xRow = raster.firstRow(containing: "[X]"),
      let xLine = raster.row(at: xRow),
      let xCol = column(of: "[X]", in: xLine)
    else {
      Issue.record(
        """
        expected `[X]` in raster — if the library has started clipping \
        positioned content outside the reader's frame, this test needs \
        to flip to assert `[X]` is absent.
        \(joined)
        """
      )
      return
    }

    #expect(
      (35...42).contains(xCol),
      """
      expected `[X]` inside the 40-wide frame near the trailing edge; \
      got col=\(xCol).
      \(joined)
      """
    )

    // Prove the positioned child remains inside the bordered frame.
    if let borderRow = raster.firstRow(containing: "▜"),
      let borderLine = raster.row(at: borderRow),
      let rightEdge = column(of: "▜", in: borderLine)
    {
      #expect(
        xCol < rightEdge,
        """
        expected `[X]` (col \(xCol)) inside the frame's right border \
        edge (col \(rightEdge)).
        \(joined)
        """
      )
    }

    // Also pin: `[X]` sits on the row just below the top border.
    // The top border is on row 2 (in the observed raster), so `[X]`
    // is on row 3 (`.position(y: 0)` lands the child on the reader's
    // first interior row).
    if let topBorderRow = raster.firstRow(containing: "▛") {
      #expect(
        xRow == topBorderRow + 1,
        "expected `[X]` one row below the top border (\(topBorderRow)); got row \(xRow)\n\(joined)"
      )
    }
  }

  /// Vacuity check: removing `.position(x:y:)` from the
  /// GeometryReader child visibly changes where `[X]` renders.
  /// Without the modifier, `[X]` should fall into the bordered
  /// region at the natural layout origin (column ~1 inside the
  /// frame), not escape to the far right.
  @Test("removing .position anchors [X] inside the frame (proves the modifier works)")
  func positionIsNonVacuous() {
    let withPosition = render(
      GeometryReaderAnchorCorner(),
      width: 80,
      height: 28,
      id: "with-position"
    ).rasterSurface
    let withoutPosition = render(
      WithoutPositionAnchorVariant(),
      width: 80,
      height: 28,
      id: "without-position"
    ).rasterSurface

    let withDump = withPosition.lines.joined(separator: "\n")
    let withoutDump = withoutPosition.lines.joined(separator: "\n")

    guard let xRowWith = withPosition.firstRow(containing: "[X]"),
      let xLineWith = withPosition.row(at: xRowWith),
      let xColWith = column(of: "[X]", in: xLineWith)
    else {
      Issue.record("WITH-position: missing [X]\n\(withDump)")
      return
    }
    guard let xRowWithout = withoutPosition.firstRow(containing: "[X]"),
      let xLineWithout = withoutPosition.row(at: xRowWithout),
      let xColWithout = column(of: "[X]", in: xLineWithout)
    else {
      Issue.record("WITHOUT-position: missing [X]\n\(withoutDump)")
      return
    }

    #expect(
      xColWith != xColWithout || xRowWith != xRowWithout,
      """
      expected `[X]` to land at different coordinates with vs without \
      `.position`; got with=(\(xRowWith),\(xColWith)) \
      without=(\(xRowWithout),\(xColWithout))
      WITH:\n\(withDump)
      WITHOUT:\n\(withoutDump)
      """
    )

    // The WITHOUT variant should have `[X]` inside the 40-wide
    // bordered frame (the natural layout origin for an
    // unmodified Text child).
    #expect(
      xColWithout < 45,
      """
      WITHOUT-position should render `[X]` inside the bordered frame \
      (col < 45); got col=\(xColWithout)
      \(withoutDump)
      """
    )
  }
}

/// Identical to `GeometryReaderAnchorCorner` except the inner `Text`
/// has no `.position(x:y:)` modifier.  Used by the A/B vacuity check.
private struct WithoutPositionAnchorVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Geometry reader anchor corner").foregroundStyle(.muted)
      GeometryReader { _ in
        Text("[X]")
      }
      .frame(width: 40, height: 5)
      .border(.separator)
    }
    .padding(1)
  }
}
