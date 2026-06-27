// Plain import: a custom Shape conformer must compile with only `geometry`.
import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

private func brailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

private func litCellCount(_ artifacts: RenderSnapshot) -> Int {
  var count = 0
  for row in artifacts.rasterSurface.cells {
    for cell in row where brailleDotCount(cell) > 0 {
      count += 1
    }
  }
  return count
}

private struct UnitPathShape: InsettableShape {
  var pathValue: Path
  var rule: FillRule = .nonZero
  var geometry: ShapeGeometry { .path(BoxedPath(pathValue), rule) }
}

/// A unit square covering the whole unit rect.
private func unitSquare() -> Path {
  var path = Path()
  path.move(to: Point(x: 0, y: 0))
  path.addLine(to: Point(x: 1, y: 0))
  path.addLine(to: Point(x: 1, y: 1))
  path.addLine(to: Point(x: 0, y: 1))
  path.close()
  return path
}

@MainActor
@Suite("Custom path stroke rasterization")
struct PathStrokeTests {

  @Test("a stroked path is hollow where a filled path is solid")
  func strokeIsHollow() {
    let stroked = DefaultRenderer().render(
      UnitPathShape(pathValue: unitSquare()).stroke(Color.white).frame(width: 20, height: 10),
      context: .init(identity: testIdentity("SquareStroke"))
    )
    let filled = DefaultRenderer().render(
      UnitPathShape(pathValue: unitSquare()).fill(Color.white).frame(width: 20, height: 10),
      context: .init(identity: testIdentity("SquareFill"))
    )
    // Center cell: filled is solid, stroked outline leaves it empty.
    let center = (row: 5, col: 10)
    #expect(brailleDotCount(filled.rasterSurface.cells[center.row][center.col]) > 0)
    #expect(brailleDotCount(stroked.rasterSurface.cells[center.row][center.col]) == 0)
    // The stroke still draws its outline (some lit cells), fewer than the fill.
    #expect(litCellCount(stroked) > 0)
    #expect(litCellCount(filled) > litCellCount(stroked))
  }

  @Test("a stroked square draws all four edges (no off-grid clipping)")
  func strokeDrawsAllEdges() {
    let stroked = DefaultRenderer().render(
      UnitPathShape(pathValue: unitSquare()).stroke(Color.white).frame(width: 20, height: 10),
      context: .init(identity: testIdentity("SquareEdges"))
    )
    let cells = stroked.rasterSurface.cells
    // A cell on each of the four edges (mid-edge) should be lit.
    #expect(brailleDotCount(cells[0][10]) > 0)  // top
    #expect(brailleDotCount(cells[9][10]) > 0)  // bottom
    #expect(brailleDotCount(cells[5][0]) > 0)  // left
    #expect(brailleDotCount(cells[5][19]) > 0)  // right
  }

  @Test("strokeBorder produces a ring distinct from the fill and stays in frame")
  func strokeBorderRing() {
    let bordered = DefaultRenderer().render(
      UnitPathShape(pathValue: unitSquare()).strokeBorder(Color.white).frame(width: 20, height: 10),
      context: .init(identity: testIdentity("SquareStrokeBorder"))
    )
    let filled = DefaultRenderer().render(
      UnitPathShape(pathValue: unitSquare()).fill(Color.white).frame(width: 20, height: 10),
      context: .init(identity: testIdentity("SquareFill2"))
    )
    // A ring: lit outline, hollow center, fewer lit cells than the solid fill.
    #expect(litCellCount(bordered) > 0)
    #expect(brailleDotCount(bordered.rasterSurface.cells[5][10]) == 0)
    #expect(litCellCount(filled) > litCellCount(bordered))
    // Stays within the placed frame.
    #expect(bordered.rasterSurface.size.width == 20)
    #expect(bordered.rasterSurface.size.height == 10)
  }
}
