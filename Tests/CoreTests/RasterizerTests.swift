import Testing

@testable import Core

@Suite
struct RasterizerTests {
  @Test("rasterize empty draw node produces empty surface")
  func rasterizeEmptyNode() {
    let rasterizer = Rasterizer()
    let draw = DrawNode(
      identity: testIdentity("empty"),
      bounds: Rect(origin: .zero, size: .zero)
    )

    let surface = rasterizer.rasterize(draw)
    #expect(surface.size == .zero)
  }

  @Test("rasterize node with bounds produces correctly sized surface")
  func rasterizeNodeWithBounds() {
    let rasterizer = Rasterizer()
    let draw = DrawNode(
      identity: testIdentity("sized"),
      bounds: Rect(origin: .zero, size: Size(width: 10, height: 5))
    )

    let surface = rasterizer.rasterize(draw)
    #expect(surface.size.width == 10)
    #expect(surface.size.height == 5)
    #expect(surface.cells.count == 5)
    #expect(surface.cells[0].count == 10)
  }

  @Test("default-styled text preserves filled background when rasterized over it")
  func defaultStyledTextPreservesFilledBackground() {
    let rasterizer = Rasterizer()
    let bounds = Rect(origin: .zero, size: Size(width: 1, height: 1))
    let draw = DrawNode(
      identity: testIdentity("overlay"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .color(.red),
          mode: .full
        ),
        .text(
          bounds: bounds,
          content: "A",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        ),
      ]
    )

    let surface = rasterizer.rasterize(draw)
    #expect(surface.cells[0][0].character == "A")
    #expect(surface.cells[0][0].style?.foregroundColor != nil)
    #expect(surface.cells[0][0].style?.backgroundColor == .red)
  }

  @Test("fully clipped descendants do not expand the raster surface extent")
  func clippedDescendantsDoNotExpandSurfaceExtent() {
    let rasterizer = Rasterizer()
    let viewportBounds = Rect(origin: .zero, size: .init(width: 3, height: 2))
    let draw = DrawNode(
      identity: testIdentity("viewport"),
      bounds: viewportBounds,
      clipBounds: viewportBounds,
      children: [
        DrawNode(
          identity: testIdentity("visible"),
          bounds: .init(origin: .zero, size: .init(width: 3, height: 1)),
          commands: [
            .text(
              bounds: .init(origin: .zero, size: .init(width: 3, height: 1)),
              content: "ABC",
              style: .init(),
              lineLimit: nil,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        ),
        DrawNode(
          identity: testIdentity("clipped"),
          bounds: .init(origin: .init(x: 0, y: 4), size: .init(width: 3, height: 1)),
          commands: [
            .text(
              bounds: .init(origin: .init(x: 0, y: 4), size: .init(width: 3, height: 1)),
              content: "XYZ",
              style: .init(),
              lineLimit: nil,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        ),
      ]
    )

    let surface = rasterizer.rasterize(draw)
    #expect(surface.size == .init(width: 3, height: 2))
    #expect(surface.lines.prefix(1) == ["ABC"])
    #expect(surface.lines.dropFirst(1).allSatisfy { $0.isEmpty })
  }
}
