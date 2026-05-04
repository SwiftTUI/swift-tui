import Testing

@testable import SwiftTUICore

@Suite
struct RasterizerTests {
  @Test("rasterize empty draw node produces empty surface")
  func rasterizeEmptyNode() {
    let rasterizer = Rasterizer()
    let draw = DrawNode(
      identity: testIdentity("empty"),
      bounds: CellRect(origin: .zero, size: .zero)
    )

    let surface = rasterizer.rasterize(draw)
    #expect(surface.size == .zero)
  }

  @Test("rasterize node with bounds produces correctly sized surface")
  func rasterizeNodeWithBounds() {
    let rasterizer = Rasterizer()
    let draw = DrawNode(
      identity: testIdentity("sized"),
      bounds: CellRect(origin: .zero, size: CellSize(width: 10, height: 5))
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
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
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
    let viewportBounds = CellRect(origin: .zero, size: .init(width: 3, height: 2))
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

  @Test("image attachments preserve logical bounds and record visible clip rects")
  func imageAttachmentsPreserveLogicalBoundsAndVisibleClipRects() throws {
    let rasterizer = Rasterizer()
    let viewportBounds = CellRect(origin: .zero, size: .init(width: 4, height: 3))
    let imageIdentity = testIdentity("scrollContent", "image")
    let imageBounds = CellRect(origin: .init(x: 0, y: -1), size: .init(width: 4, height: 4))
    let draw = DrawNode(
      identity: testIdentity("viewport"),
      bounds: viewportBounds,
      clipBounds: viewportBounds,
      children: [
        DrawNode(
          identity: imageIdentity,
          bounds: imageBounds,
          commands: [
            .image(
              bounds: imageBounds,
              identity: imageIdentity,
              payload: .init(source: .path("demo.png"))
            )
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let attachment = try #require(surface.imageAttachments.first)

    #expect(surface.imageAttachments.count == 1)
    #expect(attachment.bounds == imageBounds)
    #expect(attachment.visibleBounds == CellRect(origin: .zero, size: .init(width: 4, height: 3)))
  }

  @Test("incremental raster reuse refines row damage to actual changed spans")
  func incrementalRasterReuseRefinesDamageToActualChangedSpans() {
    let rasterizer = Rasterizer()
    let rowBounds = CellRect(origin: .zero, size: .init(width: 10, height: 1))
    let previousDraw = DrawNode(
      identity: testIdentity("row"),
      bounds: rowBounds,
      commands: [
        .text(
          bounds: rowBounds,
          content: "0123456789",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )
    let previousSurface = rasterizer.rasterize(previousDraw)
    let draw = DrawNode(
      identity: testIdentity("row"),
      bounds: rowBounds,
      commands: [
        .text(
          bounds: rowBounds,
          content: "0123X56789",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      draw,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [4..<5])])
    )

    #expect(result.surface.lines == ["0123X56789"])
    #expect(
      result.presentationDamage?.textRows == [
        .init(row: 0, columnRanges: [4..<5])
      ])
  }

  @Test("incremental raster reuse preserves clears inside refined damage spans")
  func incrementalRasterReusePreservesClearRanges() {
    let rasterizer = Rasterizer()
    let rowBounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))
    let previousDraw = DrawNode(
      identity: testIdentity("row"),
      bounds: rowBounds,
      commands: [
        .text(
          bounds: rowBounds,
          content: "ABCD",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )
    let previousSurface = rasterizer.rasterize(previousDraw)
    let draw = DrawNode(
      identity: testIdentity("row"),
      bounds: rowBounds,
      commands: [
        .text(
          bounds: rowBounds,
          content: "ABX",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      draw,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [2..<4])])
    )

    #expect(result.surface.lines == ["ABX"])
    #expect(
      result.presentationDamage?.textRows == [
        .init(row: 0, columnRanges: [2..<4])
      ])
  }

  // MARK: - Visible-identity collection

  @Test("visible identity collection records only identities not fully clipped")
  func visibleIdentityCollectionRespectsClip() {
    // This is the geometric predicate the run loop uses to gate
    // animation tick scheduling: an identity whose placed bounds are
    // entirely outside an ancestor's clipBounds must NOT appear in
    // the "visible identities" set, so an animation that affects only
    // that identity can be recognised as "quiescent against the clip"
    // and skip requesting another tick deadline.
    let rasterizer = Rasterizer()
    let viewportIdentity = testIdentity("scrollViewport")
    let visibleIdentity = testIdentity("scrollContent", "visibleRow")
    let clippedIdentity = testIdentity("scrollContent", "clippedRow")
    let viewportBounds = CellRect(origin: .zero, size: .init(width: 3, height: 2))
    let draw = DrawNode(
      identity: viewportIdentity,
      bounds: viewportBounds,
      clipBounds: viewportBounds,
      children: [
        DrawNode(
          identity: visibleIdentity,
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
          identity: clippedIdentity,
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

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      draw,
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )

    #expect(result.visibleIdentities.contains(viewportIdentity))
    #expect(result.visibleIdentities.contains(visibleIdentity))
    #expect(!result.visibleIdentities.contains(clippedIdentity))
  }

  @Test("identity moves into visible set when ancestor clip expands")
  func visibleIdentityReappearsWhenClipExpands() {
    // When a scroll view is resized or scrolled so that content
    // previously outside the viewport slides in, the next paint walk
    // must include that identity in the visible set so the run loop
    // can re-arm the animation tick deadline.
    let rasterizer = Rasterizer()
    let viewportIdentity = testIdentity("scrollViewport")
    let movingIdentity = testIdentity("scrollContent", "movingRow")
    func drawTree(clipHeight: Int) -> DrawNode {
      let clip = CellRect(origin: .zero, size: .init(width: 3, height: clipHeight))
      return DrawNode(
        identity: viewportIdentity,
        bounds: clip,
        clipBounds: clip,
        children: [
          DrawNode(
            identity: movingIdentity,
            bounds: .init(origin: .init(x: 0, y: 3), size: .init(width: 3, height: 1)),
            commands: [
              .text(
                bounds: .init(origin: .init(x: 0, y: 3), size: .init(width: 3, height: 1)),
                content: "XYZ",
                style: .init(),
                lineLimit: nil,
                truncationMode: .tail,
                wrappingStrategy: .wordBoundary
              )
            ]
          )
        ]
      )
    }

    // Frame 1: viewport is 2 rows tall, movingRow sits at y=3 so it is
    // outside the clip and must not be in the visible set.
    let frame1 = rasterizer.rasterizeCollectingVisibleIdentities(
      drawTree(clipHeight: 2),
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )
    #expect(!frame1.visibleIdentities.contains(movingIdentity))

    // Frame 2: viewport expands to 5 rows tall, movingRow is now in
    // the clip and must appear in the visible set so the tick loop
    // can resume.
    let frame2 = rasterizer.rasterizeCollectingVisibleIdentities(
      drawTree(clipHeight: 5),
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )
    #expect(frame2.visibleIdentities.contains(movingIdentity))
  }
}
