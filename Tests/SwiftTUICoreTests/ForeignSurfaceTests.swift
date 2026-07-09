import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite("Foreign surface rasterization")
struct ForeignSurfaceTests {
  struct StaticPayload: ForeignSurfacePayload {
    let grid: ForeignGrid
  }

  @Test("foreign surface cells appear at the right bounds")
  func foreignSurfaceBlit() {
    let cells: [[RasterCell]] = [
      [RasterCell(character: "A"), RasterCell(character: "B")],
      [RasterCell(character: "C"), RasterCell(character: "D")],
    ]
    let payload = StaticPayload(
      grid: ForeignGrid(
        size: CellSize(width: 2, height: 2),
        cells: cells
      )
    )
    let command: DrawCommand = .foreignSurface(
      bounds: CellRect(origin: CellPoint(x: 1, y: 1), size: CellSize(width: 2, height: 2)),
      payload: payload
    )

    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(
      DrawNode(
        identity: testIdentity("root"),
        bounds: CellRect(origin: .zero, size: CellSize(width: 4, height: 4)),
        commands: [command]
      )
    )

    #expect(surface.cells[1][1].character == "A")
    #expect(surface.cells[1][2].character == "B")
    #expect(surface.cells[2][1].character == "C")
    #expect(surface.cells[2][2].character == "D")
    #expect(surface.cells[0][0].character == RasterCell.empty.character)
  }
}
