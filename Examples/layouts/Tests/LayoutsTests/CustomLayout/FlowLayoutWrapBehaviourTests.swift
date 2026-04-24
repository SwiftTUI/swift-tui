import TerminalUI
import Testing

@testable import Layouts

/// A/B variant: same outer shape as ``FlowLayoutWrap`` but the
/// custom ``FlowLayout`` containers are replaced by `HStack`s.
/// `HStack` does not wrap — at width 30 the children clip / overflow
/// rather than spilling onto a second row, so the marker-row count
/// is the same regardless of the proposed width.  This proves the
/// width-driven row count in the canonical raster comes from
/// `FlowLayout`'s wrap algorithm, not from incidental layout.
@MainActor
private struct FlowLayoutWrapFlattenedVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("Flow layout wrap").foregroundStyle(.muted)
      Text("at width 30").foregroundStyle(.muted)
      HStack(spacing: 1) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: 30)
      .border(.separator)
      Text("at width 60").foregroundStyle(.muted)
      HStack(spacing: 1) {
        ForEach(0..<8, id: \.self) { i in
          Text("[item \(i)]")
        }
      }
      .frame(width: 60)
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct FlowLayoutWrapBehaviourTests {
  /// Each `[item N]` cell is 8 cells wide.  At width 30 the
  /// container fits ~3 cells per row (3 × 8 + 2 × 1 = 26 ≤ 30,
  /// next cell would overflow → wrap), producing 3 marker rows.
  /// At width 60 the container fits ~6 cells per row (6 × 8 + 5 × 1
  /// = 53 ≤ 60), producing 2 marker rows.  We pin the qualitative
  /// invariant: width-30 produces strictly more marker rows than
  /// width-60, and width-30 produces ≥ 2 marker rows (i.e. the
  /// wrap actually fired).
  ///
  /// Observed raster (excerpt) at 80×30:
  ///
  /// ```
  /// Flow layout wrap
  /// at width 30
  /// ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
  /// ▌  [item 0] [item 1] [item 2]  ▐
  /// ▌                              ▐
  /// ▌  [item 3] [item 4] [item 5]  ▐
  /// ▌                              ▐
  /// ▌  [item 6] [item 7]           ▐
  /// ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟
  /// at width 60
  /// ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜
  /// ▌   [item 0] [item 1] [item 2] [item 3] [item 4] [item 5]    ▐
  /// ▌                                                            ▐
  /// ▌   [item 6] [item 7]                                        ▐
  /// ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟
  /// ```
  @Test("FlowLayout wraps more rows under a narrow proposal than under a wide one")
  func wrapIsWidthDriven() {
    let raster = render(FlowLayoutWrap(), width: 80, height: 30).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // Find rows containing the `[item ` marker prefix — these are
    // the wrapped marker rows produced by the two FlowLayouts.
    let markerRows = raster.rows(containing: "[item ")
    #expect(
      markerRows.count >= 5,
      """
      expected at least 5 marker rows total (3 from the width-30 \
      flow + 2 from the width-60 flow); got \(markerRows.count). \
      If this fails, the FlowLayout has stopped wrapping.
      \(joined)
      """
    )

    // The width-30 container appears first in source order, so its
    // marker rows are the first contiguous block of marker rows.
    // Find the bordered frame for the width-30 container by
    // anchoring on the "at width 30" header.
    guard let header30Row = raster.firstRow(containing: "at width 30"),
      let header60Row = raster.firstRow(containing: "at width 60")
    else {
      Issue.record("missing header markers in raster\n\(joined)")
      return
    }
    let rowsInWidth30 = markerRows.filter { $0 > header30Row && $0 < header60Row }.count
    let rowsInWidth60 = markerRows.filter { $0 > header60Row }.count

    #expect(
      rowsInWidth30 >= 2,
      """
      expected the width-30 FlowLayout container to produce ≥ 2 \
      marker rows (the wrap fired); got \(rowsInWidth30).
      \(joined)
      """
    )
    #expect(
      rowsInWidth60 >= 1,
      """
      expected the width-60 FlowLayout container to produce ≥ 1 \
      marker row (single row of as many cells as fit); got \(rowsInWidth60).
      \(joined)
      """
    )
    #expect(
      rowsInWidth30 > rowsInWidth60,
      """
      expected the width-30 container to produce strictly more \
      marker rows than the width-60 container (wrap is width \
      driven); got width30=\(rowsInWidth30) width60=\(rowsInWidth60).
      \(joined)
      """
    )
  }

  /// A/B vacuity: substituting `HStack` for `FlowLayout` removes
  /// the wrap.  An `HStack` does not break onto new rows under a
  /// tight `.frame(width:)` — it overflows / clips instead — so
  /// the width-30 container in the variant produces at most one
  /// marker row.  The "width-30 produces strictly more marker
  /// rows than width-60" invariant from ``wrapIsWidthDriven`` no
  /// longer holds in the variant.
  @Test("replacing FlowLayout with HStack removes the row-wrap")
  func flowLayoutIsNonVacuous() {
    let withFlow = render(
      FlowLayoutWrap(),
      width: 80,
      height: 30,
      id: "with-flow"
    ).rasterSurface
    let withoutFlow = render(
      FlowLayoutWrapFlattenedVariant(),
      width: 80,
      height: 30,
      id: "without-flow"
    ).rasterSurface

    let withDump = withFlow.lines.joined(separator: "\n")
    let withoutDump = withoutFlow.lines.joined(separator: "\n")

    let withMarkerRows = withFlow.rows(containing: "[item ").count
    let withoutMarkerRows = withoutFlow.rows(containing: "[item ").count

    #expect(
      withMarkerRows > withoutMarkerRows,
      """
      WITH-FlowLayout should produce more marker rows than \
      WITHOUT-FlowLayout (wrap vs no wrap). \
      Got with=\(withMarkerRows) without=\(withoutMarkerRows).
      WITH:\n\(withDump)
      WITHOUT:\n\(withoutDump)
      """
    )
    // And the WITH variant must produce more than 2 marker rows
    // (the canonical raster shows 3 + 2 = 5).  The WITHOUT variant
    // should produce ≤ 2 (one row per HStack container, possibly
    // fewer if the width-30 row is empty/clipped).
    #expect(
      withMarkerRows >= 4,
      "WITH-FlowLayout should produce at least 4 marker rows; got \(withMarkerRows)\n\(withDump)"
    )
    #expect(
      withoutMarkerRows <= 2,
      """
      WITHOUT-FlowLayout (HStack) should produce at most 2 marker rows; \
      got \(withoutMarkerRows). If HStack now wraps, this A/B is no \
      longer a valid vacuity check.
      \(withoutDump)
      """
    )
  }
}
