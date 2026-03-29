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
}
