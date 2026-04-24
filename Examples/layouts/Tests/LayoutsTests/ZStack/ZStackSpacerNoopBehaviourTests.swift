import TerminalUI
import Testing

@testable import Layouts

/// A variant that REPLACES `Spacer` with a `Rectangle()` — which, with
/// no frame, accepts the full proposed size and therefore causes its
/// containing `ZStack` to stretch edge-to-edge.  Used by the A/B
/// vacuity check to show that when a child DOES claim space, the
/// border around the ZStack grows accordingly.
@MainActor
private struct ZStackGreedyChildVariant: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("ZStack spacer noop").foregroundStyle(.muted)
      ZStack {
        Rectangle().fill(Color.blue)
        Text("[X]")
      }
      .border(.separator)
    }
    .padding(1)
  }
}

@MainActor
@Suite
struct ZStackSpacerNoopBehaviourTests {
  /// A `Spacer` placed directly inside a `ZStack` must be a no-op for
  /// sizing — the stack hugs its non-Spacer child (`Text("[X]")`,
  /// 3 cells wide) rather than stretching to the full proposed width.
  ///
  /// A `.border(.separator)` wraps the ZStack to make its measured
  /// footprint visible.  Pinned via the raster:
  ///   - The `[X]` glyphs land on a single row.
  ///   - The ZStack's painted footprint is narrow — the separator
  ///     glyphs (`─` top edge, `│` left/right edges) that bound the
  ///     ZStack never cross the full 80-cell width.
  ///
  /// If this test fails with "border spans the full width", the
  /// library allocates the full proposal to Spacer inside ZStack
  /// (vs SwiftUI's layout-neutral Spacer in an overlay context) —
  /// file as a finding in BEHAVIOUR_FINDINGS.md.
  @Test("Spacer inside ZStack is layout-neutral: border hugs [X], not the full width")
  func spacerDoesNotClaimSpaceInZStack() {
    let width = 80
    let raster = render(
      ZStackSpacerNoop(),
      width: width,
      height: 10
    ).rasterSurface
    let joined = raster.lines.joined(separator: "\n")

    // `[X]` should appear exactly once, on a single row.
    guard let xRow = raster.firstRow(containing: "[X]"),
      let xLine = raster.row(at: xRow),
      let xCol = column(of: "[X]", in: xLine)
    else {
      Issue.record("expected `[X]` in raster\n\(joined)")
      return
    }

    // Find the border rows ABOVE and BELOW `[X]`.  The separator
    // style renders with half-block glyphs (`▛ ▜ ▙ ▟ ▀ ▄ ▌ ▐`) in
    // this library, not the light/heavy box-drawing set.  We accept
    // either glyph family to keep the assertion robust to styling
    // changes.
    let topCornerGlyphs: Set<Character> = [
      "┌", "┏", "╭", "┍", "┎", "▛", "▀",
    ]
    let bottomCornerGlyphs: Set<Character> = [
      "└", "┗", "╰", "┕", "┖", "▙", "▄",
    ]
    var topRow: Int? = nil
    var bottomRow: Int? = nil
    for row in 0..<raster.cells.count {
      let line = raster.cells[row]
      let hasTopCorner = line.contains { topCornerGlyphs.contains($0.character) }
      let hasBottomCorner = line.contains { bottomCornerGlyphs.contains($0.character) }
      if hasTopCorner, topRow == nil, row < xRow { topRow = row }
      if hasBottomCorner, row > xRow { bottomRow = row }
    }

    guard let topRow, let bottomRow else {
      Issue.record(
        """
        expected separator-border corner glyphs around `[X]` (top above, bottom below); \
        xRow=\(xRow)
        \(joined)
        """
      )
      return
    }

    // Border footprint: measure width via the top edge row's first and
    // last non-space cells.  If Spacer claimed the full proposed width
    // the footprint would be ~= width; a layout-neutral Spacer means
    // the footprint hugs `[X]` (≈ 5 cells including the two side edges).
    let topCells = raster.cells[topRow]
    let leftEdge = topCells.firstIndex { $0.character != " " } ?? 0
    let rightEdge = topCells.lastIndex { $0.character != " " } ?? 0
    let borderWidth = rightEdge - leftEdge + 1

    // `[X]` is 3 cells; outer padding(1) adds 1 cell each side of the
    // VStack (not of the border itself).  The ZStack's border should
    // hug `[X]` tightly: inner 3 cells + 2 border sides = 5 cells.
    // Allow ±2 for rounding / alignment.
    #expect(
      borderWidth >= 3,
      "border width (\(borderWidth)) should include `[X]` and its sides\n\(joined)"
    )
    #expect(
      borderWidth <= 10,
      """
      border width (\(borderWidth)) is far larger than [X]'s natural size \
      (expected ~5). Spacer appears to have claimed space inside the ZStack, \
      contradicting SwiftUI's layout-neutral Spacer semantics in overlay \
      contexts. File finding in BEHAVIOUR_FINDINGS.md.
      \(joined)
      """
    )

    // Sanity: the border height is small (1 content row + 2 sides = 3).
    let borderHeight = bottomRow - topRow + 1
    #expect(
      borderHeight >= 3,
      "border height (\(borderHeight)) should include [X] row plus top/bottom edges\n\(joined)"
    )
    #expect(
      borderHeight <= 6,
      """
      border height (\(borderHeight)) is far larger than expected (~3). Spacer \
      appears to have claimed vertical space inside the ZStack.
      \(joined)
      """
    )

    // And the [X] glyph sits within the border footprint, not at the
    // extreme right of an 80-wide stretch.
    #expect(
      xCol < 30,
      "`[X]` column (\(xCol)) should sit near the left where a tight ZStack hugs it\n\(joined)"
    )
  }

  /// A/B non-vacuity: swap the `Spacer` for a bare `Rectangle()` (no
  /// frame), which DOES accept the full proposed size.  The border
  /// around THAT ZStack should span nearly the full terminal width,
  /// proving that the primary test's "narrow border" finding for the
  /// Spacer variant is not a false green.
  @Test("a greedy (non-Spacer) ZStack child DOES stretch the border full-width")
  func greedyChildStretchesBorder() {
    let width = 80
    let spacerRaster = render(
      ZStackSpacerNoop(),
      width: width,
      height: 10,
      id: "spacer"
    ).rasterSurface
    let greedyRaster = render(
      ZStackGreedyChildVariant(),
      width: width,
      height: 10,
      id: "greedy"
    ).rasterSurface

    func borderWidth(_ raster: RasterSurface) -> Int? {
      let topCornerGlyphs: Set<Character> = [
        "┌", "┏", "╭", "┍", "┎", "▛", "▀",
      ]
      for row in 0..<raster.cells.count {
        let cells = raster.cells[row]
        if cells.contains(where: { topCornerGlyphs.contains($0.character) }) {
          let left = cells.firstIndex { $0.character != " " } ?? 0
          let right = cells.lastIndex { $0.character != " " } ?? 0
          return right - left + 1
        }
      }
      return nil
    }

    let spacerWidth = borderWidth(spacerRaster)
    let greedyWidth = borderWidth(greedyRaster)

    #expect(
      spacerWidth != nil,
      "spacer variant: missing top-border row\n\(spacerRaster.lines.joined(separator: "\n"))"
    )
    #expect(
      greedyWidth != nil,
      "greedy variant: missing top-border row\n\(greedyRaster.lines.joined(separator: "\n"))"
    )

    guard let spacerWidth, let greedyWidth else { return }

    // Sanity: the Spacer variant hugs [X] (≈5 cells); the greedy
    // Rectangle variant spans significantly wider.  If these are
    // equal, Spacer is claiming the same space as Rectangle — which
    // would invalidate the primary test's conclusion.
    #expect(
      greedyWidth > spacerWidth + 20,
      """
      expected the greedy-child border (\(greedyWidth)) to be much wider \
      than the Spacer border (\(spacerWidth)); the A/B difference proves \
      Spacer is layout-neutral in a ZStack.
      SPACER:
      \(spacerRaster.lines.joined(separator: "\n"))
      GREEDY:
      \(greedyRaster.lines.joined(separator: "\n"))
      """
    )
  }
}
