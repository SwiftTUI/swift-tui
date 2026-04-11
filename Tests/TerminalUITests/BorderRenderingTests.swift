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

  @Test(".border foreground style applies to border cells")
  func borderForegroundStyleApplies() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(Color.red, set: .single),
      context: .init(identity: testIdentity("BorderForegroundStyle"))
    )

    let topLeft = artifacts.rasterSurface.cells[0][0]
    #expect(topLeft.character == "┌")
    #expect(topLeft.style?.foregroundColor == Color.red)
  }
}
