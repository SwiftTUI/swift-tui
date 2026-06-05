// Plain (non-@testable, non-SPI) import: a custom Shape conformer must compile
// with only `geometry`, getting the SPI-hidden kindName/insetAmount defaults.
import SwiftTUIViews
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Returns the number of Braille dots lit in a raster cell, or 0 if the cell
/// holds no Braille glyph.
private func brailleDotCount(_ cell: RasterCell) -> Int {
  guard let scalar = cell.character.unicodeScalars.first?.value,
    scalar >= 0x2800,
    scalar <= 0x28FF
  else {
    return 0
  }
  return Int(scalar - 0x2800).nonzeroBitCount
}

/// A custom shape carrying a normalized unit-rect path. (Phase 6 adds the
/// `path(in:)` authoring sugar; here we exercise `.path` geometry directly.)
private struct UnitPathShape: Shape {
  var pathValue: Path
  var rule: FillRule = .nonZero
  var geometry: ShapeGeometry { .path(BoxedPath(pathValue), rule) }
}

/// A unit triangle with its base along the top edge and apex at bottom-center.
private func unitTriangle() -> Path {
  var path = Path()
  path.move(to: Point(x: 0, y: 0))
  path.addLine(to: Point(x: 1, y: 0))
  path.addLine(to: Point(x: 0.5, y: 1))
  path.close()
  return path
}

/// A unit pentagram (star polygon {5/2}) centered in the unit square. Its
/// central pentagon is filled under `.nonZero` but empty under `.evenOdd`.
private func unitPentagram() -> Path {
  let v0 = Point(x: 0.5, y: 0.05)
  let v1 = Point(x: 0.928, y: 0.361)
  let v2 = Point(x: 0.765, y: 0.864)
  let v3 = Point(x: 0.235, y: 0.864)
  let v4 = Point(x: 0.072, y: 0.361)
  var path = Path()
  path.move(to: v0)
  path.addLine(to: v2)
  path.addLine(to: v4)
  path.addLine(to: v1)
  path.addLine(to: v3)
  path.close()
  return path
}

@MainActor
@Suite("Custom path fill rasterization")
struct PathFillTests {

  // MARK: - Route A (Braille subpixel scanline fill)

  @Test("a filled triangle lights interior cells and leaves exterior corners empty")
  func triangleFill() {
    let artifacts = DefaultRenderer().render(
      UnitPathShape(pathValue: unitTriangle()).fill(Color.white)
        .frame(width: 10, height: 5),
      context: .init(identity: testIdentity("TriangleFill"))
    )
    let cells = artifacts.rasterSurface.cells
    // Interior, just below the wide base, near horizontal center.
    #expect(brailleDotCount(cells[1][5]) > 0)
    // Bottom corners are well outside the narrow apex region.
    #expect(brailleDotCount(cells[4][0]) == 0)
    #expect(brailleDotCount(cells[4][9]) == 0)
  }

  @Test("pentagram fills its center under nonZero but not under evenOdd")
  func pentagramWindingRules() {
    let nonZero = DefaultRenderer().render(
      UnitPathShape(pathValue: unitPentagram(), rule: .nonZero).fill(Color.white)
        .frame(width: 16, height: 8),
      context: .init(identity: testIdentity("PentagramNonZero"))
    )
    let evenOdd = DefaultRenderer().render(
      UnitPathShape(pathValue: unitPentagram(), rule: .evenOdd).fill(Color.white)
        .frame(width: 16, height: 8),
      context: .init(identity: testIdentity("PentagramEvenOdd"))
    )
    let nonZeroCenter = brailleDotCount(nonZero.rasterSurface.cells[4][8])
    let evenOddCenter = brailleDotCount(evenOdd.rasterSurface.cells[4][8])
    #expect(nonZeroCenter > evenOddCenter)
    #expect(nonZeroCenter > 0)
  }

  @Test("an empty path renders nothing without crashing")
  func emptyPathFill() {
    let artifacts = DefaultRenderer().render(
      UnitPathShape(pathValue: Path()).fill(Color.white).frame(width: 6, height: 3),
      context: .init(identity: testIdentity("EmptyPath"))
    )
    for row in artifacts.rasterSurface.cells {
      for cell in row {
        #expect(brailleDotCount(cell) == 0)
      }
    }
  }

  // MARK: - Route B (cell-walk containment) + agreement

  @Test("shapeContains agrees with the filled silhouette on clear interior/exterior cells")
  func routeAgreement() {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 10, height: 5))
    let geometry = ShapeGeometry.path(BoxedPath(unitTriangle()), .nonZero)

    // Route B: cell-walk containment.
    let interiorContained = rasterizer.shapeContains(
      pointX: 5, pointY: 1, in: bounds, geometry: geometry)
    let exteriorContained = rasterizer.shapeContains(
      pointX: 0, pointY: 4, in: bounds, geometry: geometry)
    #expect(interiorContained == true)
    #expect(exteriorContained == false)

    // Route A: the subpixel fill of the same shape.
    let artifacts = DefaultRenderer().render(
      UnitPathShape(pathValue: unitTriangle()).fill(Color.white)
        .frame(width: 10, height: 5),
      context: .init(identity: testIdentity("RouteAgreement"))
    )
    let cells = artifacts.rasterSurface.cells
    // The two routes agree at clearly-interior and clearly-exterior cells.
    #expect((brailleDotCount(cells[1][5]) > 0) == interiorContained)
    #expect((brailleDotCount(cells[4][0]) > 0) == exteriorContained)
  }
}
