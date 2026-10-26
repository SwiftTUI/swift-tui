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

  // STUI-741: a public custom Shape whose path holds one far, finite point
  // trapped the renderer (`Rasterizer.roundToInt`) before any stroke work.
  @Test(
    "a custom path with one far finite point strokes, dashes, trims and insets its visible part")
  func farFinitePathPointStrokesVisiblePart() async {
    await #expect(processExitsWith: .success) {
      await MainActor.run { checkFarFinitePathPointStrokes() }
    }
  }

  // STUI-1268: a finite unit point so far out that scaling it to subpixels
  // overflows drew nothing. It now draws what the same shape with a far but
  // representable point draws: stroked, dashed, trimmed, inset and filled.
  @Test("a custom path whose unit coordinates overflow the subpixel scale draws like a far one")
  func overflowingPathPointDrawsLikeAFarFinitePoint() {
    func line(to far: Double) -> UnitPathShape {
      var path = Path()
      path.move(to: Point(x: 0, y: 0.5))
      path.addLine(to: Point(x: far, y: 0.5))
      return UnitPathShape(pathValue: path)
    }
    func wedge(_ far: Double) -> UnitPathShape {
      var path = Path()
      path.move(to: .zero)
      path.addLine(to: Point(x: far, y: 0))
      path.addLine(to: Point(x: 0, y: 1))
      path.close()
      return UnitPathShape(pathValue: path)
    }
    let finite = line(to: 1e300)
    let overflowing = line(to: 1.5e308)
    let dash = StrokeStyle(dash: [1.2, 1.2])
    #expect(
      farPointDotRows(overflowing.stroke(Color.white), "OverflowSolid")
        == [[0, 0, 0, 0], [2, 2, 2, 2]])
    #expect(
      farPointDotRows(overflowing.stroke(Color.white, style: dash), "OverflowDash")
        == farPointDotRows(finite.stroke(Color.white, style: dash), "FiniteDash"))
    for (from, to) in [(0.0, 0.5), (0.5, 1.0)] {
      #expect(
        farPointDotRows(overflowing.trim(from: from, to: to).stroke(Color.white), "OverflowTrim")
          == farPointDotRows(finite.trim(from: from, to: to).stroke(Color.white), "FiniteTrim"),
        "trim \(from)...\(to)")
    }
    let inset = farPointDotRows(wedge(1.5e308).strokeBorder(Color.white), "OverflowInset")
    #expect(inset == farPointDotRows(wedge(1e300).strokeBorder(Color.white), "FiniteInset"))
    #expect(inset.joined().reduce(0, +) > 0)
    #expect(
      farPointDotRows(wedge(1.5e308).fill(Color.white), "OverflowFill")
        == farPointDotRows(wedge(1e300).fill(Color.white), "FiniteFill"))
    // Clip and tile coverage uses the fill's scanline.
    var triangle = Path()
    triangle.move(to: .zero)
    triangle.addLine(to: Point(x: 1, y: 0))
    triangle.addLine(to: Point(x: 1, y: 1.5e308))
    triangle.close()
    for y in 0..<2 {
      for x in 0..<4 {
        #expect(
          Rasterizer().pathContainsCell(
            triangle, rule: .nonZero, cellRelX: x, cellRelY: y, subpixelWidth: 8,
            subpixelHeight: 8), "cell \(x), \(y)")
      }
    }
  }

  // STUI-1249: a sloped segment whose endpoints both lie far outside the frame
  // keeps its position: the stroke and the fill draw the in-range shape with
  // the same exact direction, whether the far points overflow the subpixel
  // scale or not.
  @Test("custom path edges with both endpoints far outside the frame keep their position")
  func farSlopedPathEdgesKeepTheirPosition() {
    func shape(_ points: [(Double, Double)], closed: Bool = false) -> UnitPathShape {
      var path = Path()
      for (index, point) in points.enumerated() {
        let p = Point(x: point.0, y: point.1)
        if index == 0 { path.move(to: p) } else { path.addLine(to: p) }
      }
      if closed { path.close() }
      return UnitPathShape(pathValue: path)
    }
    let diagonal = farPointDotRows(shape([(0, 0), (1, 1)]).stroke(Color.white), "NearDiagonal")
    #expect(diagonal.joined().reduce(0, +) == 8)
    for far in [1e300, 1.7e308] {
      #expect(
        farPointDotRows(shape([(-far, -far), (far, far)]).stroke(Color.white), "FarDiagonal")
          == diagonal, "far \(far)")
    }
    // Half-plane above the diagonal: power-of-two vertices keep the near
    // fill's crossings exact.
    let nearFill = farPointDotRows(
      shape([(-2, -2), (2, 2), (-2, 2)], closed: true).fill(Color.white), "NearHalfPlane")
    #expect(nearFill.joined().reduce(0, +) > 0)
    for far in [1e300, 1.7e308] {
      #expect(
        farPointDotRows(
          shape([(-far, -far), (far, far), (-far, far)], closed: true).fill(Color.white),
          "FarHalfPlane") == nearFill, "far \(far)")
    }
  }
}

/// Renders a 4 x 2 cell frame and returns the Braille dot count of each cell.
@MainActor
private func farPointDotRows(_ view: some View, _ name: String) -> [[Int]] {
  let snapshot = DefaultRenderer().render(
    view.frame(width: 4, height: 2), context: .init(identity: testIdentity("FarPoint", name)))
  return snapshot.rasterSurface.cells.map { $0.map(brailleDotCount) }
}

@MainActor
private func checkFarFinitePathPointStrokes() {
  var line = Path()
  line.move(to: Point(x: 0, y: 0.5))
  line.addLine(to: Point(x: 1e300, y: 0.5))
  let shape = UnitPathShape(pathValue: line)
  // Subpixel row 4 (0.5 of the inclusive 0...7 range, rounded) is the top
  // dot row of the second cell row: two dots per cell.
  let solid = farPointDotRows(shape.stroke(Color.white), "Solid")
  #expect(solid == [[0, 0, 0, 0], [2, 2, 2, 2]])
  // Dash runs of 1.2 cells, measured from the path start: no run boundary
  // falls on a subpixel's track position (multiples of half a cell). The
  // visible part dashes exactly as a path that ends at the frame edge.
  let dash = StrokeStyle(dash: [1.2, 1.2])
  let dashed = farPointDotRows(shape.stroke(Color.white, style: dash), "Dash")
  #expect(dashed == [[0, 0, 0, 0], [2, 1, 1, 2]])
  var near = Path()
  near.move(to: Point(x: 0, y: 0.5))
  near.addLine(to: Point(x: 1, y: 0.5))
  #expect(
    dashed
      == farPointDotRows(UnitPathShape(pathValue: near).stroke(Color.white, style: dash), "Near"))
  let trimmed = farPointDotRows(shape.trim(from: 0, to: 0.5).stroke(Color.white), "Trim")
  #expect(trimmed == solid)
  var wedge = Path()
  wedge.move(to: .zero)
  wedge.addLine(to: Point(x: 1e300, y: 0))
  wedge.addLine(to: Point(x: 0, y: 1))
  wedge.close()
  let inset = farPointDotRows(UnitPathShape(pathValue: wedge).strokeBorder(Color.white), "Inset")
  #expect(inset.joined().reduce(0, +) > 0)
  let filled = farPointDotRows(UnitPathShape(pathValue: wedge).fill(Color.white), "Fill")
  #expect(filled.joined().reduce(0, +) > inset.joined().reduce(0, +))
  // Non-finite paths are unusable and draw nothing, stroked, dashed or filled.
  for (index, bad) in [Double.nan, .infinity].enumerated() {
    var path = Path()
    path.move(to: Point(x: 0, y: 0.5))
    path.addLine(to: Point(x: bad, y: 0.5))
    let shape = UnitPathShape(pathValue: path)
    #expect(
      farPointDotRows(shape.stroke(Color.white), "Bad\(index)").joined().allSatisfy { $0 == 0 })
    #expect(
      farPointDotRows(shape.stroke(Color.white, style: dash), "BadDash\(index)").joined()
        .allSatisfy { $0 == 0 })
    #expect(
      farPointDotRows(shape.fill(Color.white), "BadFill\(index)").joined().allSatisfy { $0 == 0 })
  }
}
