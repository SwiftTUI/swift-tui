import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Test("MeshGradient paints a rectangle with spatially varying background colors")
func meshGradientRectangleRaster() throws {
  let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 4))
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-rectangle"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .meshGradient(rasterTestMesh()),
          mode: .full
        )
      ]
    ))

  let leading = try #require(surface.cells[0][0].style?.backgroundColor)
  let trailing = try #require(surface.cells[0][7].style?.backgroundColor)
  let bottom = try #require(surface.cells[3][0].style?.backgroundColor)
  #expect(leading != trailing)
  #expect(leading != bottom)
  #expect(trailing.red > leading.red)
  #expect(bottom.green > leading.green)
}

@Test("MeshGradient reaches the curved Braille fill path")
func meshGradientCurvedRaster() {
  let bounds = CellRect(origin: .zero, size: .init(width: 10, height: 6))
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-circle"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .ellipse,
          insetAmount: 0,
          style: .meshGradient(rasterTestMesh()),
          mode: .full
        )
      ]
    ))

  let painted = surface.cells.flatMap { $0 }.filter { $0.character != " " }
  #expect(!painted.isEmpty)
  #expect(painted.allSatisfy { $0.style?.foregroundColor != nil })
  #expect(Set(painted.compactMap { $0.style?.foregroundColor }).count > 1)
}

@Test("TileStyle prepares mesh foreground and background for per-cell sampling")
func meshGradientTileRaster() throws {
  let bounds = CellRect(origin: .zero, size: .init(width: 6, height: 3))
  let tile = TileStyle(
    .dots,
    foreground: rasterTestMesh(),
    background: MeshGradient(
      width: 2,
      height: 2,
      points: rasterIdentityMeshPoints(),
      colors: [.black, .blue, .green, .white],
      background: .clear,
      smoothsColors: false
    )
  )
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-tile"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .tileStyle(tile),
          mode: .full
        )
      ]
    ))

  #expect(surface.cells.flatMap { $0 }.allSatisfy { $0.character == "·" })
  let first = try #require(surface.cells[0][0].style)
  let last = try #require(surface.cells[2][5].style)
  #expect(first.foregroundColor != last.foregroundColor)
  #expect(first.backgroundColor != last.backgroundColor)
}

@Test("MeshGradient clipping leaves cells outside the clip untouched")
func meshGradientClipRaster() {
  let bounds = CellRect(origin: .zero, size: .init(width: 6, height: 2))
  let clip = CellRect(origin: .zero, size: .init(width: 3, height: 2))
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-clip"),
      bounds: bounds,
      clipBounds: clip,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .meshGradient(rasterTestMesh()),
          mode: .full
        )
      ]
    ),
    minimumSize: bounds.size
  )

  #expect(surface.cells[0][2].style?.backgroundColor != nil)
  #expect(surface.cells[0][3].style == nil)
}

@Test("MeshGradient paints custom paths and curved strokes")
func meshGradientPathAndStrokeRaster() {
  let bounds = CellRect(origin: .zero, size: .init(width: 10, height: 5))
  var triangle = Path()
  triangle.move(to: Point(x: 0.5, y: 0))
  triangle.addLine(to: Point(x: 1, y: 1))
  triangle.addLine(to: Point(x: 0, y: 1))
  triangle.close()
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-path-stroke"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .path(BoxedPath(triangle), .nonZero),
          insetAmount: 0,
          style: .meshGradient(rasterTestMesh()),
          mode: .full
        ),
        .stroke(
          bounds: bounds,
          geometry: .ellipse,
          insetAmount: 0,
          style: .meshGradient(rasterTestMesh()),
          strokeStyle: StrokeStyle(),
          strokeBorder: false
        ),
      ]
    )
  )

  let painted = surface.cells.flatMap { $0 }.filter { $0.character != " " }
  #expect(!painted.isEmpty)
  #expect(painted.allSatisfy { $0.style?.foregroundColor != nil })
  #expect(Set(painted.compactMap { $0.style?.foregroundColor }).count > 2)
}

@Test("MeshGradient paints layout borders with spatial color")
func meshGradientBorderRaster() throws {
  let bounds = CellRect(origin: .zero, size: .init(width: 8, height: 4))
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-border"),
      bounds: bounds,
      postCommands: [
        .border(
          bounds: bounds,
          set: .single,
          foreground: BorderEdgeStyle(rasterTestMesh()),
          background: nil,
          blend: nil,
          blendPhase: 0,
          sides: .all
        )
      ]
    )
  )

  let leading = try #require(surface.cells[0][0].style?.foregroundColor)
  let trailing = try #require(surface.cells[0][7].style?.foregroundColor)
  let bottom = try #require(surface.cells[3][0].style?.foregroundColor)
  #expect(leading != trailing)
  #expect(leading != bottom)
}

@Test("MeshGradient alpha participates in blend-mode compositing")
func meshGradientTransparencyAndBlendRaster() throws {
  let bounds = CellRect(origin: .zero, size: .init(width: 4, height: 2))
  let translucent = MeshGradient(
    width: 2,
    height: 2,
    points: rasterIdentityMeshPoints(),
    colors: [
      .red.opacity(0.5), .green.opacity(0.5),
      .blue.opacity(0.5), .white.opacity(0.5),
    ],
    background: .clear,
    smoothsColors: false
  )
  let surface = Rasterizer().rasterize(
    DrawNode(
      identity: testIdentity("mesh-blend-root"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .color(.black),
          mode: .full
        )
      ],
      children: [
        DrawNode(
          identity: testIdentity("mesh-blend-child"),
          bounds: bounds,
          drawEffects: .init([.blendMode(.screen)]),
          commands: [
            .fill(
              bounds: bounds,
              geometry: .rectangle,
              insetAmount: 0,
              style: .meshGradient(translucent),
              mode: .full
            )
          ]
        )
      ]
    )
  )

  let leading = try #require(surface.cells[0][0].style?.backgroundColor)
  let trailing = try #require(surface.cells[0][3].style?.backgroundColor)
  #expect(leading.alpha == 1)
  #expect(trailing.alpha == 1)
  #expect(leading != trailing)
  #expect(leading != .black)
  #expect(trailing != .black)
}

private func rasterTestMesh() -> MeshGradient {
  MeshGradient(
    width: 2,
    height: 2,
    points: rasterIdentityMeshPoints(),
    colors: [
      Color(red: 0, green: 0, blue: 0),
      Color(red: 1, green: 0, blue: 0),
      Color(red: 0, green: 1, blue: 0),
      Color(red: 1, green: 1, blue: 1),
    ],
    background: .clear,
    smoothsColors: false
  )
}

private func rasterIdentityMeshPoints() -> [SIMD2<Float>] {
  [.init(0, 0), .init(1, 0), .init(0, 1), .init(1, 1)]
}
