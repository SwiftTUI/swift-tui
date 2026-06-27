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

private struct CustomTriangle: Shape {
  func path(in rect: Rect) -> Path {
    var path = Path()
    path.move(to: Point(x: rect.origin.x, y: rect.origin.y))
    path.addLine(to: Point(x: rect.maxX, y: rect.origin.y))
    path.addLine(to: Point(x: rect.origin.x + rect.size.width / 2, y: rect.maxY))
    path.close()
    return path
  }
}

/// The custom-path normalized geometry is evaluated once (against the unit
/// rect) but scaled into the placed frame at raster time. These tests prove
/// that appearance is frame-relative: the same shape re-projects when its
/// frame changes, the way a SwiftUI Shape responds to its frame.
@MainActor
@Suite("Custom path frame reactivity")
struct PathFrameReactivityTests {

  @Test("the same path renders differently at different frame sizes")
  func reprojectsAcrossFrameSizes() {
    let small = DefaultRenderer().render(
      CustomTriangle().fill(Color.white).frame(width: 8, height: 4),
      context: .init(identity: testIdentity("TriangleSmall"))
    )
    let large = DefaultRenderer().render(
      CustomTriangle().fill(Color.white).frame(width: 24, height: 12),
      context: .init(identity: testIdentity("TriangleLarge"))
    )
    #expect(small.rasterSurface != large.rasterSurface)
    #expect(small.rasterSurface.size.width == 8)
    #expect(large.rasterSurface.size.width == 24)
    // The shape scales up with the frame: a larger frame lights more cells.
    #expect(litCellCount(large) > litCellCount(small))
  }

  @Test("the path fills proportionally to its frame (frame-relative)")
  func proportionalToFrame() {
    // A unit square fills its whole frame; the lit cell count tracks the area.
    let square = { (w: Int, h: Int) -> RenderSnapshot in
      DefaultRenderer().render(
        CustomSquare().fill(Color.white).frame(width: w, height: h),
        context: .init(identity: testIdentity("Square\(w)x\(h)"))
      )
    }
    let small = square(6, 3)
    let wide = square(18, 3)
    // Same height, 3× width → markedly more lit cells (fills the wider frame).
    #expect(litCellCount(wide) > litCellCount(small) * 2)
  }
}

private struct CustomSquare: Shape {
  func path(in rect: Rect) -> Path {
    Path(rect)
  }
}
