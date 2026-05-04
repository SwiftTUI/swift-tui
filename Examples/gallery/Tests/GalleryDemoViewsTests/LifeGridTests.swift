import Foundation
import SwiftTUI
import Testing

@testable import GalleryDemoViews

// Unit-level regressions for the Conway's Life data model and zoom
// translation. The tab's full visual rendering is covered indirectly
// by the gallery snapshot suites; these tests exercise the parts most
// likely to silently break — step rules, toroidal wrap, and
// pointer-to-game-cell mapping under each zoom mode.

@MainActor
@Suite
struct LifeGridTests {

  // MARK: - Step rules (B3/S23)

  @Test("blinker oscillator flips between vertical and horizontal each step")
  func blinkerOscillates() {
    var grid = LifeGrid(width: 8, height: 8)
    // Vertical blinker at (3, 2..4)
    grid.set(3, 2, true)
    grid.set(3, 3, true)
    grid.set(3, 4, true)

    grid.step()
    // Horizontal: (2..4, 3)
    #expect(grid.at(2, 3))
    #expect(grid.at(3, 3))
    #expect(grid.at(4, 3))
    #expect(!grid.at(3, 2))
    #expect(!grid.at(3, 4))

    grid.step()
    // Back to vertical
    #expect(grid.at(3, 2))
    #expect(grid.at(3, 3))
    #expect(grid.at(3, 4))
  }

  @Test("block stays alive forever (still life)")
  func blockIsStillLife() {
    var grid = LifeGrid(width: 8, height: 8)
    grid.set(2, 2, true)
    grid.set(3, 2, true)
    grid.set(2, 3, true)
    grid.set(3, 3, true)
    let popBefore = grid.population

    for _ in 0..<5 { grid.step() }

    #expect(grid.population == popBefore)
    #expect(grid.at(2, 2))
    #expect(grid.at(3, 2))
    #expect(grid.at(2, 3))
    #expect(grid.at(3, 3))
    #expect(grid.generation == 5)
  }

  @Test("isolated live cell dies (underpopulation)")
  func loneCellDies() {
    var grid = LifeGrid(width: 8, height: 8)
    grid.set(4, 4, true)
    grid.step()
    #expect(!grid.at(4, 4))
    #expect(grid.population == 0)
  }

  @Test("toroidal wrap: cells at the edge see neighbors on the opposite edge")
  func toroidalWrap() {
    // A horizontal blinker straddling the right edge should still
    // oscillate. Place it at (6, 0), (7, 0), (0, 0) on an 8-wide grid.
    var grid = LifeGrid(width: 8, height: 8)
    grid.set(6, 0, true)
    grid.set(7, 0, true)
    grid.set(0, 0, true)

    grid.step()
    // After step, blinker rotates: now cells at (7, 7), (7, 0), (7, 1).
    // (Vertical column at x=7 wrapping y=7→0→1.)
    #expect(grid.at(7, 7))
    #expect(grid.at(7, 0))
    #expect(grid.at(7, 1))
  }

  // MARK: - Resize preserves visible region

  @Test("shrinking the grid clears cells outside the new bounds")
  func resizeClearsOutsideRegion() {
    var grid = LifeGrid(width: 16, height: 16)
    grid.set(10, 10, true)
    grid.set(2, 2, true)

    grid.resize(width: 4, height: 4)

    // (2,2) is preserved
    #expect(grid.at(2, 2))
    // (10,10) is now out of bounds; the API returns false for
    // out-of-bounds reads regardless, but we also want enlarging
    // back to not resurrect the value.
    grid.resize(width: 16, height: 16)
    #expect(!grid.at(10, 10))
  }

  // MARK: - Randomize seeding

  @Test("seeded randomize is deterministic and population is roughly density")
  func seededRandomize() {
    var a = LifeGrid(width: 32, height: 32)
    var b = LifeGrid(width: 32, height: 32)
    a.randomize(density: 0.3, seed: 42)
    b.randomize(density: 0.3, seed: 42)

    var matches = 0
    for y in 0..<32 {
      for x in 0..<32 where a.at(x, y) == b.at(x, y) {
        matches += 1
      }
    }
    #expect(matches == 32 * 32)

    // Population should be in a reasonable band around the target.
    let cellCount = 32 * 32
    let pop = a.population
    let low = Int(Double(cellCount) * 0.20)
    let high = Int(Double(cellCount) * 0.40)
    #expect(pop >= low)
    #expect(pop <= high)
  }
}

@MainActor
@Suite
struct LifeZoomTests {
  // MARK: - braille mapping (2x4 game cells per terminal cell)

  @Test("braille: terminal cell (3, 1) maps the four-row sub-grid to game rows 4..7")
  func brailleMapsToGameRows() {
    let zoom = LifeZoom.braille
    let grid = (width: 100, height: 100)

    // Four points within terminal cell (3, 1), each at a different
    // sub-row. x fraction stays in the left sub-column (sx = 0).
    let p0 = Point(x: 3.0,  y: 1.0)   // sy = 0 → game (6, 4)
    let p1 = Point(x: 3.0,  y: 1.25)  // sy = 1 → game (6, 5)
    let p2 = Point(x: 3.0,  y: 1.50)  // sy = 2 → game (6, 6)
    let p3 = Point(x: 3.0,  y: 1.75)  // sy = 3 → game (6, 7)

    #expect(zoom.gameCell(at: p0, gridSize: grid)?.y == 4)
    #expect(zoom.gameCell(at: p1, gridSize: grid)?.y == 5)
    #expect(zoom.gameCell(at: p2, gridSize: grid)?.y == 6)
    #expect(zoom.gameCell(at: p3, gridSize: grid)?.y == 7)
    // x-mapping for the left column.
    #expect(zoom.gameCell(at: p0, gridSize: grid)?.x == 6)

    // Right sub-column (fx > 0.5): same terminal cell, sx = 1 → game x = 7.
    let p4 = Point(x: 3.6, y: 1.0)
    #expect(zoom.gameCell(at: p4, gridSize: grid)?.x == 7)
  }

  // MARK: - half-cell mapping (1x2 game cells per terminal cell)

  @Test("halfCell: y fraction selects upper or lower row")
  func halfCellMapsRows() {
    let zoom = LifeZoom.halfCell
    let grid = (width: 100, height: 100)

    let upper = Point(x: 5.0, y: 2.2) // sy = 0 → game (5, 4)
    let lower = Point(x: 5.0, y: 2.7) // sy = 1 → game (5, 5)
    #expect(zoom.gameCell(at: upper, gridSize: grid)?.y == 4)
    #expect(zoom.gameCell(at: lower, gridSize: grid)?.y == 5)
    #expect(zoom.gameCell(at: upper, gridSize: grid)?.x == 5)
  }

  // MARK: - square mapping (1 game cell per 2 terminal cells)

  @Test("squareCell: terminal x is halved to game x")
  func squareCellMapsX() {
    let zoom = LifeZoom.squareCell
    let grid = (width: 100, height: 100)

    // Terminal cells (4, _) and (5, _) both fall on game x = 2.
    #expect(zoom.gameCell(at: Point(x: 4.0, y: 1.0), gridSize: grid)?.x == 2)
    #expect(zoom.gameCell(at: Point(x: 5.5, y: 1.0), gridSize: grid)?.x == 2)
    #expect(zoom.gameCell(at: Point(x: 6.0, y: 1.0), gridSize: grid)?.x == 3)
  }

  // MARK: - bounds rejection

  @Test("out-of-bounds points return nil")
  func outOfBoundsReturnsNil() {
    let zoom = LifeZoom.halfCell
    let grid = (width: 8, height: 8)

    #expect(zoom.gameCell(at: Point(x: -1.0, y: 0.0), gridSize: grid) == nil)
    #expect(zoom.gameCell(at: Point(x: 0.0, y: -0.5), gridSize: grid) == nil)
    #expect(zoom.gameCell(at: Point(x: 100.0, y: 0.0), gridSize: grid) == nil)
  }

  // MARK: - capability gating

  @Test("braille and halfCell require Unicode; squareCell does not")
  func capabilityGating() {
    #expect(LifeZoom.braille.requiresUnicode)
    #expect(LifeZoom.halfCell.requiresUnicode)
    #expect(!LifeZoom.squareCell.requiresUnicode)
  }
}

@MainActor
@Suite
struct LifeRendererTests {
  @Test("braille renderer emits one Unicode codepoint in U+2800..U+28FF per terminal cell")
  func brailleEmitsBraillePoints() {
    var grid = LifeGrid(width: 4, height: 4)
    grid.set(0, 0, true)
    grid.set(1, 0, true)
    grid.set(0, 1, true)

    let output = LifeRenderer.render(
      grid: grid,
      zoom: .braille,
      visibleSize: CellSize(width: 2, height: 1)
    )
    // Output should contain exactly two characters (the row).
    #expect(output.count == 2)

    for scalar in output.unicodeScalars {
      #expect(scalar.value >= 0x2800 && scalar.value <= 0x28FF)
    }
  }

  @Test("half-cell: alive top + dead bottom emits ▀")
  func halfCellTopGlyph() {
    var grid = LifeGrid(width: 1, height: 2)
    grid.set(0, 0, true)
    grid.set(0, 1, false)

    let output = LifeRenderer.render(
      grid: grid,
      zoom: .halfCell,
      visibleSize: CellSize(width: 1, height: 1)
    )
    #expect(output == "\u{2580}")
  }

  @Test("square: alive cell renders as two FULL BLOCK glyphs")
  func squareAliveGlyph() {
    var grid = LifeGrid(width: 1, height: 1)
    grid.set(0, 0, true)

    let output = LifeRenderer.render(
      grid: grid,
      zoom: .squareCell,
      visibleSize: CellSize(width: 2, height: 1)
    )
    #expect(output == "\u{2588}\u{2588}")
  }
}
