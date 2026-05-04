import Testing

@testable import SwiftTUICore
@testable import SwiftTUI
@testable import SwiftTUIViews

@MainActor
@Suite("TileStyle rendering")
struct TileStyleRenderingTests {
  @Test("Rectangle filled with TileStyle light shade writes ░ at every cell")
  func rectangleTileStyleLight() {
    let view =
      Rectangle()
      .fill(TileStyle(.lightShade, foreground: .white))
      .frame(width: 4, height: 2)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleLight"))
    )
    for y in 0..<2 {
      for x in 0..<4 {
        #expect(artifacts.rasterSurface.cells[y][x].character == "░")
      }
    }
  }

  @Test("TileStyle with custom glyph and background")
  func tileStyleCustomGlyphAndBackground() {
    let view =
      Rectangle()
      .fill(TileStyle(.dots, foreground: .red, background: .black))
      .frame(width: 3, height: 1)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleCustom"))
    )
    for x in 0..<3 {
      let cell = artifacts.rasterSurface.cells[0][x]
      #expect(cell.character == "·")
      #expect(cell.style?.foregroundColor == Color.red)
      #expect(cell.style?.backgroundColor == Color.black)
    }
  }

  @Test("TileStyle on rounded rectangle respects the shape mask")
  func tileStyleRoundedRectangle() {
    let view =
      RoundedRectangle(cornerRadius: 1)
      .fill(TileStyle(.mediumShade, foreground: .white))
      .frame(width: 5, height: 3)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleRounded"))
    )
    #expect(artifacts.rasterSurface.cells[1][2].character == "▒")
    let topLeft = artifacts.rasterSurface.cells[0][0]
    #expect(topLeft.character == " ")
    #expect(topLeft.style == nil)
  }

  @Test("TileStyle on Circle writes its glyph at cells inside the disc")
  func tileStyleOnCircleRendersGlyph() {
    let view =
      Circle()
      .fill(TileStyle(.lightShade, foreground: .red))
      .frame(width: 10, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleCircleRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[2][5].character == "░")
    #expect(cells[2][5].style?.foregroundColor == Color.red)

    var litCount = 0
    for row in cells {
      for cell in row where cell.character == "░" {
        litCount += 1
      }
    }
    #expect(litCount > 0)
    #expect(cells[0][0].character != "░")
    #expect(cells[0][9].character != "░")
  }

  @Test("TileStyle on Ellipse writes its glyph at cells inside the ellipse")
  func tileStyleOnEllipseRendersGlyph() {
    let view =
      Ellipse()
      .fill(TileStyle(.mediumShade, foreground: .blue))
      .frame(width: 12, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleEllipseRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[2][6].character == "▒")
    #expect(cells[2][6].style?.foregroundColor == Color.blue)
    #expect(cells[0][0].character != "▒")
    #expect(cells[0][11].character != "▒")
  }

  @Test("TileStyle on Capsule writes its glyph at cells inside the pill")
  func tileStyleOnCapsuleRendersGlyph() {
    let view =
      Capsule()
      .fill(TileStyle(.heavyShade, foreground: .green))
      .frame(width: 12, height: 5)
    let artifacts = DefaultRenderer().render(
      view,
      context: .init(identity: testIdentity("TileStyleCapsuleRenders"))
    )
    let cells = artifacts.rasterSurface.cells
    #expect(cells[2][6].character == "▓")
    #expect(cells[2][6].style?.foregroundColor == Color.green)
    #expect(cells[0][0].character != "▓")
  }
}
