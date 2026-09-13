import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Drawing rendering regressions")
struct DrawingRenderingRegressionTests {
  @Test("STUI-59: line-created surfaces emit every row on the first repaint")
  func lineSurfaceExtent() {
    for requested in [CellSize.zero, .init(width: 1, height: 1), .init(width: 8, height: 4)] {
      let surface = RasterSurface(size: requested, lines: ["Hello", "界!"])
      #expect(
        surface.size == .init(width: max(5, requested.width), height: max(2, requested.height)))
      let output = fullRepaintWriteSteps(for: surface, capabilityProfile: .previewASCII).joined()
      #expect(output.contains("Hello"))
      #expect(output.contains("!"))
    }
    #expect(RasterSurface(lines: ["界!"]).size == .init(width: 3, height: 1))
    #expect(RasterSurface(lines: ["", ""]).size == .init(width: 0, height: 2))
    #expect(RasterSurface(lines: []).size == .zero)
  }

  @Test("STUI-57: curved stroke backgrounds sample each cell", arguments: [0, 1, 2, 3])
  func curvedStrokeGradient(kind: Int) throws {
    let bounds = CellRect(origin: .zero, size: .init(width: 40, height: 12))
    let geometry: ShapeGeometry
    switch kind {
    case 0: geometry = .circle
    case 1: geometry = .ellipse
    case 2: geometry = .capsule
    default:
      geometry = .path(
        .init(Path(ellipseIn: .init(origin: .zero, size: .init(width: 1, height: 1)))),
        .nonZero)
    }
    let gradient = LinearGradient(colors: [.red, .blue], startPoint: .leading, endPoint: .trailing)
    let draw = DrawNode(
      identity: testIdentity("StrokeGradient"), bounds: bounds,
      commands: [
        .stroke(
          bounds: bounds, geometry: geometry, insetAmount: 0,
          style: AnyShapeStyle(Color.white), strokeStyle: StrokeStyle(), strokeBorder: true,
          backgroundStyle: BorderBackgroundStyle(gradient))
      ])
    let rasterizer = Rasterizer()
    let surface = rasterizer.rasterize(draw)
    var colors: Set<Color> = []
    for row in surface.cells {
      for cell in row where cell.character != " " {
        if let color = cell.style?.backgroundColor { colors.insert(color) }
      }
    }
    #expect(colors.count > 2)
    let replay = rasterizer.rasterizeCollectingVisibleIdentities(
      draw, minimumSize: .zero, previousSurface: surface,
      damage: .init(textRows: [
        .init(row: 2, columnRanges: [0..<40]), .init(row: 9, columnRanges: [0..<40]),
      ]))
    #expect(replay.surface == surface)
  }

  @Test(
    "STUI-86: tile circles stay inside solid circles at non-square metrics",
    arguments: [
      CellPixelMetrics.estimated,
      .init(width: 10, height: 16, source: .reported),
      .init(width: 6, height: 14, source: .reported),
      .init(width: 12, height: 16, source: .reported),
    ])
  func tileCircleContainment(metrics: CellPixelMetrics) {
    for (width, height) in [(12, 6), (24, 15), (6, 16), (20, 6), (1, 1), (2, 1)] {
      let solid = DefaultRenderer().render(
        Circle().fill(Color.red).frame(width: width, height: height)
          .environment(\.cellPixelMetrics, metrics)
      ).rasterSurface
      let tiled = DefaultRenderer().render(
        Circle().fill(TileStyle(.init(rows: ["x"]), foreground: Color.red))
          .frame(width: width, height: height)
          .environment(\.cellPixelMetrics, metrics)
      ).rasterSurface
      var count = 0
      for (solidRow, tileRow) in zip(solid.cells, tiled.cells) {
        for (paint, tile) in zip(solidRow, tileRow) where tile.character == "x" {
          count += 1
          #expect(paint.character != " " && paint.character != "\u{2800}")
        }
      }
      if width >= 6 && height >= 6 { #expect(count > 0) }
    }
  }

  @Test("STUI-124: Canvas fades default, explicit, sample and direct-cell colors once")
  func canvasColorsFade() throws {
    let surface = DefaultRenderer().render(
      Canvas(OpacityDrawing()).frame(width: 4, height: 1)
        .foregroundStyle(Color.red).opacity(0.5).opacity(0.5)
    ).rasterSurface
    for x in 0..<4 {
      let style = try #require(surface.cells[0][x].style)
      #expect(style.foregroundColor?.alpha == 0.25)
      if x > 0 { #expect(style.backgroundColor?.alpha == 0.125) }
    }
  }
}

private struct OpacityDrawing: CanvasDrawing {
  func draw(into context: inout CanvasContext) {
    context.setPixel(at: .init(x: 0.25, y: 0.125), foreground: context.foreground)
    context.foreground = .green
    context.background = Color.blue.opacity(0.5)
    context.setPixel(at: .init(x: 1.25, y: 0.125))
    context.setPixel(
      at: .init(x: 2.25, y: 0.125), foreground: .red, background: Color.blue.opacity(0.5))
    context.setCell(
      at: .init(x: 3, y: 0), character: "x", foreground: .red, background: Color.blue.opacity(0.5))
  }
}
