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
    // and should not carry the pattern glyph.
    #expect(artifacts.rasterSurface.cells[0][0].character != "▒")
  }
}
