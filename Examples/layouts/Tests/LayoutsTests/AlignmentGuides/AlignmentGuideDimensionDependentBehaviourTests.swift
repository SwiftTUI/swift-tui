import SwiftTUI
import Testing

@testable import Layouts

/// A/B variant: same three boxed children, but the HStack uses
/// `alignment: .top` instead of `.bottom`. With `.top` the three
/// boxes hang from a common top edge, so their bottom borders
/// land at three different rows (1-, 2-, 3-row tall boxes).
@MainActor
private struct AlignmentGuideDimensionDependentTopVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 1) {
      Text("Alignment guide dimension dependent").foregroundStyle(.muted)
      HStack(alignment: .top, spacing: 2) {
        Text("[A]").border(.separator)
        Text("[B]\n[B]").border(.separator)
        Text("[C]\n[C]\n[C]").border(.separator)
      }
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct AlignmentGuideDimensionDependentBehaviourTests {
  /// The HStack uses `alignment: .bottom`, whose default guide is
  /// `{ d in d.height }` — the canonical dimension-dependent guide.
  /// Each child reports its bottom guide at its own height, and
  /// the HStack pulls those guides to a common raster row.  The
  /// three boxes therefore share a bottom-border row even though
  /// their heights differ (1/2/3 content rows).
  ///
  /// Observed raster (60×14 viewport, layout has `.padding(1)` and
  /// `.border(.separator)` on the HStack):
  ///
  /// ```
  /// [3] | ▛▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▀▜|
  /// [4] | ▌              ▛▀▀▀▜▐|
  /// [5] | ▌       ▛▀▀▀▜  ▌[C]▐▐|
  /// [6] | ▌▛▀▀▀▜  ▌[B]▐  ▌[C]▐▐|
  /// [7] | ▌▌[A]▐  ▌[B]▐  ▌[C]▐▐|
  /// [8] | ▌▙▄▄▄▟  ▙▄▄▄▟  ▙▄▄▄▟▐|
  /// [9] | ▙▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▄▟|
  /// ```
  ///
  /// `[A]` is one row tall, so its content row IS its last row.
  /// `[B]` is two rows tall, so its second `[B]` is its last
  /// content row.  `[C]` is three rows tall, so its third `[C]`
  /// is its last.  All three "last content row" indices coincide;
  /// equivalently their bottom borders land on the same row.
  @Test("HStack(.bottom) bottom-aligns mixed-height boxes")
  func bottomBordersShareRow() {
    let raster = render(
      AlignmentGuideDimensionDependent(),
      width: 60,
      height: 14
    ).rasterSurface
    let dump = raster.lines.joined(separator: "\n")

    guard let aLast = raster.lastRow(containing: "[A]"),
      let bLast = raster.lastRow(containing: "[B]"),
      let cLast = raster.lastRow(containing: "[C]")
    else {
      Issue.record("missing one or more box markers in raster\n\(dump)")
      return
    }

    #expect(
      aLast == bLast,
      """
      expected [A]'s last content row (\(aLast)) to equal [B]'s last \
      content row (\(bLast)) — bottom alignment should pull both \
      boxes' bottom edges to the same raster row.
      \(dump)
      """
    )
    #expect(
      bLast == cLast,
      """
      expected [B]'s last content row (\(bLast)) to equal [C]'s last \
      content row (\(cLast)).
      \(dump)
      """
    )
  }

  /// A/B vacuity: replacing `alignment: .bottom` with `.top`
  /// inverts the alignment.  With `.top` the three boxes share
  /// their TOP edges; their bottoms then sit at three distinct
  /// rows (the 1-, 2-, and 3-row-tall content blocks each end at
  /// different absolute rows).
  @Test("Replacing .bottom with .top spreads the bottom edges to distinct rows")
  func bottomAlignmentIsNonVacuous() {
    let withBottom = render(
      AlignmentGuideDimensionDependent(),
      width: 60,
      height: 14,
      id: "with-bottom"
    ).rasterSurface
    let withTop = render(
      AlignmentGuideDimensionDependentTopVariant(),
      width: 60,
      height: 14,
      id: "with-top"
    ).rasterSurface

    let bottomDump = withBottom.lines.joined(separator: "\n")
    let topDump = withTop.lines.joined(separator: "\n")

    guard let bAlast = withBottom.lastRow(containing: "[A]"),
      let bBlast = withBottom.lastRow(containing: "[B]"),
      let bClast = withBottom.lastRow(containing: "[C]")
    else {
      Issue.record("WITH-bottom raster missing markers\n\(bottomDump)")
      return
    }
    guard let tAlast = withTop.lastRow(containing: "[A]"),
      let tBlast = withTop.lastRow(containing: "[B]"),
      let tClast = withTop.lastRow(containing: "[C]")
    else {
      Issue.record("WITH-top raster missing markers\n\(topDump)")
      return
    }

    // WITH-bottom: A/B/C last rows must coincide.
    #expect(
      bAlast == bBlast && bBlast == bClast,
      """
      WITH-bottom expected [A]/[B]/[C] last rows equal; got \
      A=\(bAlast) B=\(bBlast) C=\(bClast)
      \(bottomDump)
      """
    )
    // WITH-top: at least two last rows must differ — the boxes
    // share their TOP edges, so their bottoms diverge.
    let topLasts = Set([tAlast, tBlast, tClast])
    #expect(
      topLasts.count > 1,
      """
      WITH-top (.top alignment) expected the three boxes' last rows \
      to land at distinct positions; got A=\(tAlast) B=\(tBlast) C=\(tClast). \
      If they all coincide here the A/B is no longer a valid vacuity check.
      \(topDump)
      """
    )
  }
}
