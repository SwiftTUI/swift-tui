import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Glyph-level assertions for the rewritten `.border(...)` view modifier.
///
/// These glyph-palette tests request outset placement explicitly where they
/// need an unobscured content interior. The public inset default is covered by
/// `BorderModifierLayoutTests`.
@MainActor
struct BorderRenderingTests {
  @Test(".border(style: .single) writes the expected corner and edge glyphs")
  func singleBorderDrawsBoxGlyphs() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(style: .single, placement: .outset),
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

  @Test(".border(style: .single) interior text is unmodified")
  func singleBorderInteriorIsUnmodified() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(style: .single, placement: .outset),
      context: .init(identity: testIdentity("BorderInterior"))
    )

    #expect(artifacts.rasterSurface.cells[1][1].character == "h")
    #expect(artifacts.rasterSurface.cells[1][2].character == "i")
  }

  @Test(".border(style: .single) paints each corner in the expected position")
  func singleBorderCornerGlyphs() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(style: .single, placement: .outset),
      context: .init(identity: testIdentity("BorderCorners"))
    )

    let cells = artifacts.rasterSurface.cells
    #expect(cells[0][0].character == "┌")
    #expect(cells[0][3].character == "┐")
    #expect(cells[2][0].character == "└")
    #expect(cells[2][3].character == "┘")
  }

  @Test(".border(style: .dashed) dashes round the perimeter")
  func dashedBorderDashesRoundThePerimeter() {
    let artifacts = DefaultRenderer().render(
      Text("aaaa").border(style: .dashed, placement: .outset),
      context: .init(identity: testIdentity("BorderDashed"))
    )

    // `.dashed` carries its rhythm as a second glyph in each edge string
    // (`"─·"`). A stroke draws one glyph per palette entry, so the set dashes
    // one unit on and one unit off instead, and the `·` gap glyph is gone.
    //
    // This test used to pin `┌─·─·┐`: the cycle restarted after each corner, so
    // the top and bottom edges both ran left to right and a phase could not
    // circulate. The pattern is now measured clockwise from the top-leading
    // corner. A vertical cell is two units long, so it is half drawn: `╷` is
    // its lower half. The 6 x 3 ring is 18 units round.
    let rows = artifacts.rasterSurface.cells.map { row in String(row.map(\.character)) }
    #expect(
      rows == [
        "┌ ─ ─╷",
        "╷aaaa╷",
        "╶ ─ ─ ",
      ])
  }

  @Test(".border(sides: [.top]) draws only the top edge")
  func topOnlyBorderDrawsOnlyTopEdge() {
    let artifacts = DefaultRenderer().render(
      Text("hi").border(style: .single, placement: .outset, sides: [.top]),
      context: .init(identity: testIdentity("BorderTopEdge"))
    )

    #expect(
      artifacts.rasterSurface.lines == [
        "──",
        "hi",
      ]
    )
  }

  @Test(".border(style: .innerHalfBlock, placement: .inset) draws into the view's outermost cells")
  func innerHalfBlockDrawsIntoOutermostCells() {
    // Explicit .inset placement means the frame does not grow —
    // the border glyphs overdraw the outermost child cells.  Rendering
    // should paint the inset glyphs without pushing the content around.
    let artifacts = DefaultRenderer().render(
      Text("hello").border(style: .innerHalfBlock, placement: .inset),
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
      Text("hi").border(Color.red, style: .single, placement: .outset),
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
      .border(style: .innerHalfBlock, placement: .inset),
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
