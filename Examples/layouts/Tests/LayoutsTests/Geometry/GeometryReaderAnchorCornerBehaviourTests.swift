import TerminalUI
import Testing

@testable import Layouts

@MainActor
@Suite
struct GeometryReaderAnchorCornerBehaviourTests {
  /// Observed raster at 80×28 (reader wrapped in
  /// `.frame(width: 40, height: 5).border(.separator)`):
  ///
  /// ```
  /// [1]  Geometry reader anchor corner|
  /// [2]  ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|                                (border ends near col 41)
  /// [3]  ▌                                        ▐                                    [X]|
  /// [4]  ▌                                        ▐|
  /// [8]  ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// Per `BEHAVIOUR_FINDINGS.md` finding #4, `proxy.size.width`
  /// equals the full terminal width (80), not the tightened frame
  /// width (40).  The `.position(x: proxy.size.width − 2)` call
  /// therefore places `[X]` at absolute column ~78 in the reader's
  /// coordinate space, which is OUTSIDE the 40-wide bordered frame.
  ///
  /// A SwiftUI-faithful outcome would place `[X]` near the
  /// top-right corner of the bordered frame (around column 38 in
  /// padded coordinates).  The library's actual raster has `[X]`
  /// near column 77 — well past the border's right edge (~ col 41).
  /// The frame does not clip `[X]`: the positioned child escapes
  /// the bordered region instead.
  ///
  /// This test pins the observed behaviour.  When finding #4 is
  /// fixed, the primary assertion should flip to check that `[X]`
  /// sits within the bordered frame (~col 38).
  @Test("[X] escapes the 40-wide frame because proxy.size reports 80 (finding #4)")
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
        to flip to assert `[X]` is absent.  See BEHAVIOUR_FINDINGS.md finding #4.
        \(joined)
        """
      )
      return
    }

    // Finding #4: proxy.size.width == 80, so
    // `.position(x: 78)` → `[X]` centered at column 78.
    // `[X]` is 3 cells wide → leading column ~77 (= 78 − 3/2).
    #expect(
      xCol >= 60,
      """
      expected `[X]` to land past column 60 (observed behaviour under \
      finding #4: proxy.size reports terminal width 80). \
      Got col=\(xCol).  When finding #4 is fixed, flip this to expect \
      `[X]` inside the 40-wide frame (leading col ~37).
      \(joined)
      """
    )

    // Prove the positioned child has ESCAPED the bordered frame.
    // The border's top-right corner glyph `▜` sits near column 41.
    if let borderRow = raster.firstRow(containing: "▜"),
      let borderLine = raster.row(at: borderRow),
      let rightEdge = column(of: "▜", in: borderLine)
    {
      #expect(
        xCol > rightEdge,
        """
        expected `[X]` (col \(xCol)) to sit past the frame's right \
        border edge (col \(rightEdge)). \
        If `[X]` lands INSIDE the frame, finding #4 may be fixed — flip \
        this assertion and close the finding.
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
