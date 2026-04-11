import Testing

@testable import Core
@testable import TerminalUI
@testable import View

@MainActor
@Suite("PatternFill rendering")
struct PatternFillRenderingTests {
  @Test("Rectangle filled with PatternFill.lightShade writes ░ at every cell")
  func rectanglePatternFillLight() {
    let view =
      Rectangle()
      .fill(PatternFill.lightShade)
      .frame(width: 4, height: 2)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillLight"))
    )
    for y in 0..<2 {
      for x in 0..<4 {
        #expect(artifacts.rasterSurface.cells[y][x].character == "░")
      }
    }
  }

  @Test("PatternFill with custom glyph and background")
  func patternFillCustomGlyphAndBackground() {
    let view =
      Rectangle()
      .fill(PatternFill(glyph: "·", foreground: .red, background: .black))
      .frame(width: 3, height: 1)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillCustom"))
    )
    for x in 0..<3 {
      let cell = artifacts.rasterSurface.cells[0][x]
      #expect(cell.character == "·")
      #expect(cell.style?.foregroundColor == Color.red)
      #expect(cell.style?.backgroundColor == Color.black)
    }
  }

  @Test("PatternFill on rounded rectangle respects the shape mask")
  func patternFillRoundedRectangle() {
    // `RoundedRectangle(cornerRadius:)` should clip the pattern to
    // its shape, so corner cells that lie outside the rounded rect
    // are NOT filled with the pattern glyph.
    let view =
      RoundedRectangle(cornerRadius: 1)
      .fill(PatternFill.mediumShade)
      .frame(width: 5, height: 3)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillRounded"))
    )
    // Interior cell at the centre should be the medium-shade glyph.
    #expect(artifacts.rasterSurface.cells[1][2].character == "▒")
    // The top-left corner cell lies outside the rounded-rect mask
    // and should be empty (no glyph, no style).
    let topLeft = artifacts.rasterSurface.cells[0][0]
    #expect(topLeft.character == " ")
    #expect(topLeft.style == nil)
  }

  @Test("PatternFill on Circle writes its glyph at cells inside the disc")
  func patternFillOnCircleRendersGlyph() {
    // Curved shapes route PatternFill through the cell-walking loop,
    // so `░` is actually written at each cell whose visual center
    // falls inside the Braille disc.  The outline is blocky — corner
    // cells that lie outside the disc stay empty.
    let view =
      Circle()
      .fill(PatternFill(glyph: "░", foreground: .red))
      .frame(width: 10, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillCircleRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    // The center cell of the bounding rect is well inside the disc.
    #expect(cells[2][5].character == "░")
    #expect(cells[2][5].style?.foregroundColor == Color.red)
    // At least a handful of cells should carry the pattern glyph.
    var litCount = 0
    for row in cells {
      for cell in row where cell.character == "░" {
        litCount += 1
      }
    }
    #expect(litCount > 0)
    // The top corners lie outside the disc mask and must stay empty.
    #expect(cells[0][0].character != "░")
    #expect(cells[0][9].character != "░")
  }

  @Test("PatternFill on Ellipse writes its glyph at cells inside the ellipse")
  func patternFillOnEllipseRendersGlyph() {
    let view =
      Ellipse()
      .fill(PatternFill(glyph: "▒", foreground: .blue))
      .frame(width: 12, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillEllipseRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    // Middle of the ellipse: should contain the medium-shade glyph.
    #expect(cells[2][6].character == "▒")
    #expect(cells[2][6].style?.foregroundColor == Color.blue)
    // A cell at an extreme corner should NOT contain the glyph.
    #expect(cells[0][0].character != "▒")
    #expect(cells[0][11].character != "▒")
  }

  @Test("PatternFill on Capsule writes its glyph at cells inside the pill")
  func patternFillOnCapsuleRendersGlyph() {
    let view =
      Capsule()
      .fill(PatternFill(glyph: "▓", foreground: .green))
      .frame(width: 12, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("PatternFillCapsuleRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    // Middle cell of a wide capsule's body is inside.
    #expect(cells[2][6].character == "▓")
    #expect(cells[2][6].style?.foregroundColor == Color.green)
    // A top-left corner cell lies outside the rounded end of the pill.
    #expect(cells[0][0].character != "▓")
  }
}
