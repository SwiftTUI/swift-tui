import Testing

@testable import Core
@testable import TerminalUI
@testable import View

/// Glyph-level assertions for the rewritten `.border(...)` view modifier.
///
/// Pinned by M2.B: the layout engine reserves frame insets equal to the
/// border set's per-side display widths, and the rasterizer paints
/// border glyphs into those reserved cells (for outset/decorative
/// placements) or into the view's outermost cells (for inset
/// placements) without ever touching the child's interior cells.
@MainActor
struct BorderRenderingTests {
  @Test(".border(set: .single) writes the expected corner and edge glyphs")
  func singleBorderDrawsBoxGlyphs() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single),
      context: .init(identity: testIdentity("BorderSingleBox"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "┌──┐",
        "│hi│",
        "└──┘",
      ]
    )
  }

  @Test(".border(set: .single) interior text is unmodified")
  func singleBorderInteriorIsUnmodified() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single),
      context: .init(identity: testIdentity("BorderInterior"))
    )

    #expect(artifacts.rasterSurface.cells[1][1].character == "h")
    #expect(artifacts.rasterSurface.cells[1][2].character == "i")
  }

  @Test(".border(set: .single) paints each corner in the expected position")
  func singleBorderCornerGlyphs() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single),
      context: .init(identity: testIdentity("BorderCorners"))
    )

    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].character == "┌")
    #expect(cells[0][3].character == "┐")
    #expect(cells[2][0].character == "└")
    #expect(cells[2][3].character == "┘")
  }

  @Test(".border(set: .dashed) cycles glyphs along the top edge")
  func dashedBorderCyclesTopEdge() {
    let artifacts = DefaultRenderer().render(
      Text("aaaa").border(set: .dashed),
      context: .init(identity: testIdentity("BorderDashed"))
    )

    // .dashed top edge is "─·" which cycles at each position along the
    // top.  Trimmed width = 4 (text) + 2 (borders) = 6.  Top edge cells
    // are at x=1..=4.
    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].character == "┌")
    #expect(cells[0][1].character == "─")
    #expect(cells[0][2].character == "·")
    #expect(cells[0][3].character == "─")
    #expect(cells[0][4].character == "·")
    #expect(cells[0][5].character == "┐")
  }

  @Test(".border(sides: [.top]) draws only the top edge")
  func topOnlyBorderDrawsOnlyTopEdge() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(set: .single, sides: [.top]),
      context: .init(identity: testIdentity("BorderTopEdge"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "──",
        "hi",
      ]
    )
  }

  @Test(".border(set: .innerHalfBlock) draws into the view's outermost cells")
  func innerHalfBlockDrawsIntoOutermostCells() {
    // .innerHalfBlock is an inset border, so the frame does not grow —
    // the border glyphs overdraw the outermost child cells.  Rendering
    // should paint the inset glyphs without pushing the content around.
    let artifacts = DefaultRenderer().render(
      Text("hello").border(set: .innerHalfBlock),
      context: .init(identity: testIdentity("BorderInnerHalfBlock"))
    )

    // Text is 5x1 and stays 5x1.  The top/bottom edges of
    // .innerHalfBlock are drawn into the same row, so for a 1-row
    // source the border glyphs clobber the row entirely.  We check the
    // width here rather than the full line content.
    #expect(artifacts.rasterSurface.size.width == 5)
    #expect(artifacts.rasterSurface.size.height == 1)
  }

  @Test(".border foreground style applies to all four edges")
  func borderForegroundStyleApplies() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(Color.red, set: .single),
      context: .init(identity: testIdentity("BorderForegroundStyle"))
    )

    // All four corners and a cell on each of the four edges should carry
    // the red foreground color.  Trimmed frame is 4x3 for "hi" + .single.
    let cells = artifacts.rasterSurface.cells
    // Corners
    #expect(cells[0][0].character == "┌")
    #expect(cells[0][0].style?.foregroundColor == Color.red)
    #expect(cells[0][3].character == "┐")
    #expect(cells[0][3].style?.foregroundColor == Color.red)
    #expect(cells[2][0].character == "└")
    #expect(cells[2][0].style?.foregroundColor == Color.red)
    #expect(cells[2][3].character == "┘")
    #expect(cells[2][3].style?.foregroundColor == Color.red)
    // One cell per edge (non-corner)
    #expect(cells[0][1].character == "─")  // top edge
    #expect(cells[0][1].style?.foregroundColor == Color.red)
    #expect(cells[2][1].character == "─")  // bottom edge
    #expect(cells[2][1].style?.foregroundColor == Color.red)
    #expect(cells[1][0].character == "│")  // left edge
    #expect(cells[1][0].style?.foregroundColor == Color.red)
    #expect(cells[1][3].character == "│")  // right edge
    #expect(cells[1][3].style?.foregroundColor == Color.red)
  }

  @Test(".border with inset placement paints glyphs into a multi-row child")
  func innerHalfBlockPaintsMultiRowChild() {
    // Use a multi-line child so the inset placement has visible space
    // to paint into.  A VStack of three short texts gives us a 3x3
    // surface where .innerHalfBlock overdraws the outer ring of cells
    // with its corner and edge glyphs, leaving only the single interior
    // cell (1,1) showing original content.
    let artifacts = DefaultRenderer().render(
      VStack(spacing: 0) {
        Text("top")
        Text("mid")
        Text("bot")
      }
      .border(set: .innerHalfBlock),
      context: .init(identity: testIdentity("BorderInsetMultiRow"))
    )

    // The frame does NOT grow — .innerHalfBlock is inset placement.
    #expect(artifacts.rasterSurface.size.width == 3)
    #expect(artifacts.rasterSurface.size.height == 3)

    let cells = artifacts.rasterSurface.cells
    // Top row: inset corner glyphs are ▗ / ▖ per
    // BorderSet.innerHalfBlock and the top edge glyph is ▄.
    #expect(cells[0][0].character == "▗")
    #expect(cells[0][1].character == "▄")
    #expect(cells[0][2].character == "▖")
    // Middle row: left / right edge glyphs overdraw the outer cells,
    // leaving only the single interior cell showing the "i" of "mid".
    #expect(cells[1][0].character == "▐")
    #expect(cells[1][1].character == "i")
    #expect(cells[1][2].character == "▌")
    // Bottom row: corner glyphs ▝ / ▘ and the bottom edge glyph ▀.
    #expect(cells[2][0].character == "▝")
    #expect(cells[2][1].character == "▀")
    #expect(cells[2][2].character == "▘")
  }
}
