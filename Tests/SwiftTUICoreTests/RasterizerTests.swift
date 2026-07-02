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

  @Test(
    "blend mode composites fill backgrounds against the current raster backdrop",
    arguments: [
      BlendMode.normal,
      BlendMode.multiply,
      BlendMode.screen,
      BlendMode.overlay,
      BlendMode.darken,
      BlendMode.lighten,
    ]
  )
  func blendModeCompositesFillBackground(mode: BlendMode) throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdrop = Color(red: 0.20, green: 0.60, blue: 0.70, profile: .linearSRGB)
    let source = Color(red: 0.80, green: 0.40, blue: 0.20, profile: .linearSRGB)
    let expected = source.composited(over: backdrop, mode: mode, workingSpace: .linearSRGB)
    let draw = DrawNode(
      identity: testIdentity("blend-root"),
      bounds: bounds,
      commands: [
        .fill(
          bounds: bounds,
          geometry: .rectangle,
          insetAmount: 0,
          style: .color(backdrop),
          mode: .full
        )
      ],
      children: [
        DrawNode(
          identity: testIdentity("blend-child"),
          bounds: bounds,
          drawEffects: .init([.blendMode(mode)]),
          commands: [
            .fill(
              bounds: bounds,
              geometry: .rectangle,
              insetAmount: 0,
              style: .color(source),
              mode: .full
            )
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    expectColor(style.backgroundColor, equals: expected)
  }

  @Test("blend mode composites text foreground against the current raster foreground")
  func blendModeCompositesTextForeground() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdropForeground = Color(red: 0.20, green: 0.60, blue: 0.70, profile: .linearSRGB)
    let sourceForeground = Color(red: 0.80, green: 0.40, blue: 0.20, profile: .linearSRGB)
    let expectedForeground = sourceForeground.composited(
      over: backdropForeground,
      mode: .screen,
      workingSpace: .linearSRGB
    )
    let draw = DrawNode(
      identity: testIdentity("blend-text-root"),
      bounds: bounds,
      commands: [
        .text(
          bounds: bounds,
          content: "B",
          style: .init(
            foregroundStyle: .color(backdropForeground), backgroundStyle: .color(.black)),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ],
      children: [
        DrawNode(
          identity: testIdentity("blend-text-child"),
          bounds: bounds,
          drawEffects: .init([.blendMode(.screen)]),
          commands: [
            .text(
              bounds: bounds,
              content: "S",
              style: .init(foregroundStyle: .color(sourceForeground)),
              lineLimit: nil,
              truncationMode: .tail,
              wrappingStrategy: .wordBoundary
            )
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    #expect(surface.cells[0][0].character == "S")
    expectColor(style.foregroundColor, equals: expectedForeground)
    #expect(style.backgroundColor == Color.black)
  }

  @Test("blend mode without a group streams each leaf against the current backdrop")
  func blendModeWithoutGroupStreamsPerLeafAgainstBackdrop() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdrop = Color(red: 0.20, green: 0.30, blue: 0.80, profile: .linearSRGB)
    let first = Color(red: 0.80, green: 0.20, blue: 0.20, profile: .linearSRGB)
    let second = Color(red: 0.20, green: 0.80, blue: 0.40, profile: .linearSRGB)
    let firstComposite = first.composited(over: backdrop, mode: .screen, workingSpace: .linearSRGB)
    let expected = second.composited(
      over: firstComposite,
      mode: .screen,
      workingSpace: .linearSRGB
    )
    let draw = DrawNode(
      identity: testIdentity("streaming-root"),
      bounds: bounds,
      commands: [fillCommand(bounds: bounds, color: backdrop)],
      children: [
        DrawNode(
          identity: testIdentity("streaming-container"),
          bounds: bounds,
          drawEffects: .init([.blendMode(.screen)]),
          children: [
            fillNode("streaming-first", bounds: bounds, color: first),
            fillNode("streaming-second", bounds: bounds, color: second),
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    expectColor(style.backgroundColor, equals: expected)
  }

  @Test("blend mode before compositingGroup does not blend the flattened group with backdrop")
  func blendModeBeforeCompositingGroupDoesNotBlendTheFlattenedGroupWithBackdrop() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdrop = Color(red: 0.15, green: 0.35, blue: 0.85, profile: .linearSRGB)
    let first = Color(red: 0.90, green: 0.30, blue: 0.20, profile: .linearSRGB)
    let second = Color(red: 0.20, green: 0.80, blue: 0.45, profile: .linearSRGB)
    let expected = second.composited(over: first, mode: .multiply, workingSpace: .linearSRGB)
    let draw = DrawNode(
      identity: testIdentity("blend-before-group-root"),
      bounds: bounds,
      commands: [fillCommand(bounds: bounds, color: backdrop)],
      children: [
        DrawNode(
          identity: testIdentity("blend-before-group"),
          bounds: bounds,
          drawEffects: .init([.blendMode(.multiply), .compositingGroup]),
          children: [
            fillNode("blend-before-group-first", bounds: bounds, color: first),
            fillNode("blend-before-group-second", bounds: bounds, color: second),
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    expectColor(style.backgroundColor, equals: expected)
  }

  @Test("blend mode after compositingGroup blends the flattened group with backdrop")
  func blendModeAfterCompositingGroupBlendsFlattenedGroupWithBackdrop() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdrop = Color(red: 0.15, green: 0.35, blue: 0.85, profile: .linearSRGB)
    let first = Color(red: 0.90, green: 0.30, blue: 0.20, profile: .linearSRGB)
    let second = Color(red: 0.20, green: 0.80, blue: 0.45, profile: .linearSRGB)
    let expected = second.composited(over: backdrop, mode: .multiply, workingSpace: .linearSRGB)
    let draw = DrawNode(
      identity: testIdentity("group-before-blend-root"),
      bounds: bounds,
      commands: [fillCommand(bounds: bounds, color: backdrop)],
      children: [
        DrawNode(
          identity: testIdentity("group-before-blend"),
          bounds: bounds,
          drawEffects: .init([.compositingGroup, .blendMode(.multiply)]),
          children: [
            fillNode("group-before-blend-first", bounds: bounds, color: first),
            fillNode("group-before-blend-second", bounds: bounds, color: second),
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    expectColor(style.backgroundColor, equals: expected)
  }

  @Test("nested compositing groups apply inner and outer blend modes in order")
  func nestedCompositingGroupsApplyInnerAndOuterBlendModesInOrder() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let rootBackdrop = Color(red: 0.20, green: 0.30, blue: 0.80, profile: .linearSRGB)
    let outerBackdrop = Color(red: 0.15, green: 0.65, blue: 0.25, profile: .linearSRGB)
    let innerSource = Color(red: 0.85, green: 0.20, blue: 0.35, profile: .linearSRGB)
    let innerComposite = innerSource.composited(
      over: outerBackdrop,
      mode: .screen,
      workingSpace: .linearSRGB
    )
    let expected = innerComposite.composited(
      over: rootBackdrop,
      mode: .multiply,
      workingSpace: .linearSRGB
    )
    let draw = DrawNode(
      identity: testIdentity("nested-group-root"),
      bounds: bounds,
      commands: [fillCommand(bounds: bounds, color: rootBackdrop)],
      children: [
        DrawNode(
          identity: testIdentity("nested-group-outer"),
          bounds: bounds,
          drawEffects: .init([.compositingGroup, .blendMode(.multiply)]),
          children: [
            fillNode("nested-group-outer-backdrop", bounds: bounds, color: outerBackdrop),
            DrawNode(
              identity: testIdentity("nested-group-inner"),
              bounds: bounds,
              drawEffects: .init([.compositingGroup, .blendMode(.screen)]),
              commands: [fillCommand(bounds: bounds, color: innerSource)]
            ),
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let style = try #require(surface.cells[0][0].style)

    expectColor(style.backgroundColor, equals: expected)
  }

  @Test("compositingGroup respects clip bounds")
  func compositingGroupRespectsClipBounds() throws {
    let rasterizer = Rasterizer()
    let rootBounds = CellRect(origin: .zero, size: CellSize(width: 2, height: 1))
    let clip = CellRect(origin: .zero, size: CellSize(width: 1, height: 1))
    let backdrop = Color(red: 0.10, green: 0.20, blue: 0.70, profile: .linearSRGB)
    let source = Color(red: 0.90, green: 0.30, blue: 0.20, profile: .linearSRGB)
    let draw = DrawNode(
      identity: testIdentity("group-clip-root"),
      bounds: rootBounds,
      commands: [fillCommand(bounds: rootBounds, color: backdrop)],
      children: [
        DrawNode(
          identity: testIdentity("group-clip"),
          bounds: rootBounds,
          clipBounds: clip,
          drawEffects: .init([.compositingGroup]),
          commands: [fillCommand(bounds: rootBounds, color: source)]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let clippedStyle = try #require(surface.cells[0][0].style)
    let retainedStyle = try #require(surface.cells[0][1].style)

    expectColor(clippedStyle.backgroundColor, equals: source)
    expectColor(retainedStyle.backgroundColor, equals: backdrop)
  }

  @Test("compositingGroup preserves wide glyph continuation cells")
  func compositingGroupPreservesWideGlyphContinuationCells() {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 2, height: 1))
    let draw = DrawNode(
      identity: testIdentity("group-wide-root"),
      bounds: bounds,
      drawEffects: .init([.compositingGroup]),
      commands: [
        .text(
          bounds: bounds,
          content: "界",
          style: .init(),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)

    #expect(surface.cells[0][0].character == "界")
    #expect(surface.cells[0][0].spanWidth == 2)
    #expect(surface.cells[0][1].continuationLeadX == 0)
  }

  @Test("compositingGroup preserves post-child inset border ordering")
  func compositingGroupPreservesPostChildInsetBorderOrdering() {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: CellSize(width: 3, height: 3))
    let draw = DrawNode(
      identity: testIdentity("group-post-border-root"),
      bounds: bounds,
      drawEffects: .init([.compositingGroup]),
      commands: [fillCommand(bounds: bounds, color: .blue)],
      postCommands: [
        .border(
          bounds: bounds,
          set: .single,
          foreground: .init(.red),
          background: nil,
          blend: nil,
          blendPhase: 0,
          sides: .all
        )
      ],
      children: [
        fillNode("group-post-border-child", bounds: bounds, color: .green)
      ]
    )

    let surface = rasterizer.rasterize(draw)

    #expect(surface.lines == ["┌─┐", "│ │", "└─┘"])
    #expect(surface.cells[0][0].style?.foregroundColor == .red)
    #expect(surface.cells[1][1].style?.backgroundColor == .green)
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
    #expect(attachment.compositing == nil)
  }

  @Test("image attachments under blend mode capture destination backdrop metadata")
  func imageAttachmentsUnderBlendModeCaptureDestinationBackdropMetadata() throws {
    let rasterizer = Rasterizer()
    let rootBounds = CellRect(origin: .zero, size: .init(width: 2, height: 1))
    let imageIdentity = testIdentity("image-blend")
    let imageBounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let draw = DrawNode(
      identity: testIdentity("image-blend-root"),
      bounds: rootBounds,
      commands: [fillCommand(bounds: rootBounds, color: .red)],
      children: [
        DrawNode(
          identity: imageIdentity,
          bounds: imageBounds,
          drawEffects: .init([.blendMode(.multiply)]),
          commands: [
            .image(
              bounds: imageBounds,
              identity: imageIdentity,
              payload: imagePayload()
            )
          ]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let attachment = try #require(surface.imageAttachments.first)
    let compositing = try #require(attachment.compositing)

    #expect(compositing.blendMode == .multiply)
    #expect(compositing.cellPixelSize == .init(width: 8, height: 16))
    #expect(compositing.destinationBackdrop.bounds == imageBounds)
    #expect(compositing.destinationBackdrop.cells == [.init(backgroundColor: .red, glyph: " ")])
    #expect(compositing.sourceBackdrop == nil)
  }

  @Test("foreground-only glyph under blended image changes backdrop signature")
  func foregroundOnlyGlyphUnderBlendedImageChangesBackdropSignature() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let imageIdentity = testIdentity("image-glyph-signature")

    func renderedCompositing(
      glyph: Character
    ) throws -> RasterImageCompositing {
      let draw = DrawNode(
        identity: testIdentity("image-glyph-signature-root"),
        bounds: bounds,
        commands: [
          .text(
            bounds: bounds,
            content: String(glyph),
            style: .init(foregroundStyle: .color(.red)),
            lineLimit: nil,
            truncationMode: .tail,
            wrappingStrategy: .wordBoundary
          )
        ],
        children: [
          DrawNode(
            identity: imageIdentity,
            bounds: bounds,
            drawEffects: .init([.blendMode(.multiply)]),
            commands: [
              .image(
                bounds: bounds,
                identity: imageIdentity,
                payload: imagePayload()
              )
            ]
          )
        ]
      )
      let attachment = try #require(rasterizer.rasterize(draw).imageAttachments.first)
      return try #require(attachment.compositing)
    }

    let first = try renderedCompositing(glyph: "A")
    let second = try renderedCompositing(glyph: "B")

    #expect(
      first.destinationBackdrop.cells
        == [.init(backgroundColor: nil, foregroundColor: .red, glyph: "A")]
    )
    #expect(
      second.destinationBackdrop.cells
        == [.init(backgroundColor: nil, foregroundColor: .red, glyph: "B")]
    )
    #expect(first.backdropSignature != second.backdropSignature)
  }

  @Test("blended image over wide glyph continuation captures the lead glyph")
  func blendedImageOverWideGlyphContinuationCapturesLeadGlyph() throws {
    let rasterizer = Rasterizer()
    let rootBounds = CellRect(origin: .zero, size: .init(width: 2, height: 1))
    let imageBounds = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 1, height: 1))
    let imageIdentity = testIdentity("image-wide-continuation")
    let draw = DrawNode(
      identity: testIdentity("image-wide-continuation-root"),
      bounds: rootBounds,
      commands: [
        .text(
          bounds: rootBounds,
          content: "界",
          style: .init(foregroundStyle: .color(.red)),
          lineLimit: nil,
          truncationMode: .tail,
          wrappingStrategy: .wordBoundary
        )
      ],
      children: [
        DrawNode(
          identity: imageIdentity,
          bounds: imageBounds,
          drawEffects: .init([.blendMode(.multiply)]),
          commands: [
            .image(
              bounds: imageBounds,
              identity: imageIdentity,
              payload: imagePayload()
            )
          ]
        )
      ]
    )

    let attachment = try #require(rasterizer.rasterize(draw).imageAttachments.first)
    let compositing = try #require(attachment.compositing)

    #expect(
      compositing.destinationBackdrop.cells
        == [
          .init(
            backgroundColor: nil,
            foregroundColor: .red,
            glyph: "界",
            spanWidth: 2,
            spanOffset: 1
          )
        ]
    )
  }

  @Test("image blend metadata preserves blend and compositingGroup ordering")
  func imageBlendMetadataPreservesBlendAndCompositingGroupOrdering() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let imageIdentity = testIdentity("image-order")

    func renderedAttachment(
      effects: DrawEffects
    ) throws -> RasterImageAttachment {
      let draw = DrawNode(
        identity: testIdentity("image-order-root"),
        bounds: bounds,
        commands: [fillCommand(bounds: bounds, color: .red)],
        children: [
          DrawNode(
            identity: testIdentity("image-order-group"),
            bounds: bounds,
            drawEffects: effects,
            commands: [fillCommand(bounds: bounds, color: .blue)],
            children: [
              DrawNode(
                identity: imageIdentity,
                bounds: bounds,
                commands: [
                  .image(
                    bounds: bounds,
                    identity: imageIdentity,
                    payload: imagePayload()
                  )
                ]
              )
            ]
          )
        ]
      )
      return try #require(rasterizer.rasterize(draw).imageAttachments.first)
    }

    let blendThenGroup = try renderedAttachment(
      effects: .init([.blendMode(.multiply), .compositingGroup])
    )
    let groupThenBlend = try renderedAttachment(
      effects: .init([.compositingGroup, .blendMode(.multiply)])
    )
    let blendThenGroupCompositing = try #require(blendThenGroup.compositing)
    let groupThenBlendCompositing = try #require(groupThenBlend.compositing)

    #expect(
      blendThenGroupCompositing.destinationBackdrop.cells == [
        .init(backgroundColor: .blue, glyph: " ")
      ])
    #expect(blendThenGroupCompositing.sourceBackdrop == nil)
    #expect(
      groupThenBlendCompositing.destinationBackdrop.cells == [
        .init(backgroundColor: .red, glyph: " ")
      ])
    #expect(
      groupThenBlendCompositing.sourceBackdrop?.cells == [.init(backgroundColor: .blue, glyph: " ")]
    )
    #expect(blendThenGroupCompositing != groupThenBlendCompositing)
  }

  @Test("presentation layers preserve cell image cell paint order")
  func presentationLayersPreserveCellImageCellPaintOrder() throws {
    let rasterizer = Rasterizer()
    let rootBounds = CellRect(origin: .zero, size: .init(width: 3, height: 1))
    let imageBounds = CellRect(origin: .init(x: 1, y: 0), size: .init(width: 1, height: 1))
    let imageIdentity = testIdentity("presentation-layer-image")
    let draw = DrawNode(
      identity: testIdentity("presentation-layer-root"),
      bounds: rootBounds,
      commands: [fillCommand(bounds: rootBounds, color: .red)],
      children: [
        DrawNode(
          identity: imageIdentity,
          bounds: imageBounds,
          commands: [
            .image(
              bounds: imageBounds,
              identity: imageIdentity,
              payload: .init(source: .path("middle.png"))
            )
          ]
        ),
        DrawNode(
          identity: testIdentity("presentation-layer-text"),
          bounds: imageBounds,
          commands: [
            .text(
              bounds: imageBounds,
              content: "T",
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

    #expect(surface.lines == [" T "])
    #expect(
      surface.presentationLayers.map(layerContentKind) == [
        "cells", "cells", "cells", "image", "cells",
      ])
    try #require(surface.presentationLayers.count > 3)
    let imageLayer = surface.presentationLayers[3]
    let textLayer = try #require(surface.presentationLayers.last)
    #expect(imageAttachment(in: imageLayer)?.identity == imageIdentity)
    #expect(cellFragment(in: textLayer)?.bounds == imageBounds)
  }

  @Test("presentation layers preserve image over image authoring order")
  func presentationLayersPreserveImageOverImageAuthoringOrder() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let backIdentity = testIdentity("presentation-image-back")
    let frontIdentity = testIdentity("presentation-image-front")
    func imageNode(
      identity: Identity,
      source: String
    ) -> DrawNode {
      DrawNode(
        identity: identity,
        bounds: bounds,
        commands: [
          .image(
            bounds: bounds,
            identity: identity,
            payload: .init(source: .path(source))
          )
        ]
      )
    }
    let draw = DrawNode(
      identity: testIdentity("presentation-image-root"),
      bounds: bounds,
      children: [
        imageNode(identity: backIdentity, source: "back.png"),
        imageNode(identity: frontIdentity, source: "front.png"),
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let layerImages = surface.presentationLayers.compactMap(imageAttachment)

    #expect(surface.imageAttachments.map(\.identity) == [backIdentity, frontIdentity])
    #expect(layerImages.map(\.identity) == [backIdentity, frontIdentity])
  }

  @Test("presentation layers carry active blend effects")
  func presentationLayersCarryActiveBlendEffects() throws {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let draw = DrawNode(
      identity: testIdentity("presentation-effect-root"),
      bounds: bounds,
      children: [
        DrawNode(
          identity: testIdentity("presentation-effect-child"),
          bounds: bounds,
          drawEffects: .init([.blendMode(.screen)]),
          commands: [fillCommand(bounds: bounds, color: .blue)]
        )
      ]
    )

    let surface = rasterizer.rasterize(draw)
    let layer = try #require(surface.presentationLayers.first)

    #expect(layer.effects == [.blendMode(.screen)])
  }

  @Test("snapshot renderer includes presentation layer descriptions")
  func snapshotRendererIncludesPresentationLayerDescriptions() {
    let rasterizer = Rasterizer()
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let imageIdentity = testIdentity("snapshot-image")
    let draw = DrawNode(
      identity: testIdentity("snapshot-root"),
      bounds: bounds,
      commands: [
        .image(
          bounds: bounds,
          identity: imageIdentity,
          payload: .init(source: .path("snapshot.png"))
        )
      ]
    )

    let snapshot = SnapshotRenderer().rasterSurface(rasterizer.rasterize(draw))

    #expect(snapshot.contains("layers=#0 image[@(0,0) 1x1 id="))
    #expect(snapshot.contains("snapshot-image"))
  }

  @Test("incremental raster reuse retains image attachments outside dirty rows")
  func incrementalRasterReuseRetainsImageAttachmentsOutsideDirtyRows() throws {
    let rasterizer = Rasterizer()
    let rootBounds = CellRect(origin: .zero, size: .init(width: 4, height: 4))
    let rowBounds = CellRect(origin: .zero, size: .init(width: 4, height: 1))
    let imageIdentity = testIdentity("image")
    let imageBounds = CellRect(origin: .init(x: 0, y: 2), size: .init(width: 4, height: 2))

    func drawTree(
      text: String
    ) -> DrawNode {
      DrawNode(
        identity: testIdentity("root"),
        bounds: rootBounds,
        children: [
          DrawNode(
            identity: testIdentity("row"),
            bounds: rowBounds,
            commands: [
              .text(
                bounds: rowBounds,
                content: text,
                style: .init(),
                lineLimit: nil,
                truncationMode: .tail,
                wrappingStrategy: .wordBoundary
              )
            ]
          ),
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
          ),
        ]
      )
    }

    let previousSurface = rasterizer.rasterize(drawTree(text: "AAAA"))
    let previousAttachment = try #require(previousSurface.imageAttachments.first)

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      drawTree(text: "BBBB"),
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [0..<4])])
    )

    let attachment = try #require(result.surface.imageAttachments.first)
    #expect(result.surface.lines.first == "BBBB")
    #expect(result.surface.imageAttachments.count == 1)
    #expect(attachment == previousAttachment)
    #expect(
      result.presentationDamage?.textRows == [
        .init(row: 0, columnRanges: [0..<4])
      ])
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

  @Test("Incremental repaint equals fresh raster across a mutation matrix")
  func incrementalRepaintEqualsFreshRaster() {
    let rasterizer = Rasterizer()
    let mutations: [CoreRasterRepaintMutation] = [
      .init(
        name: "single row text edit",
        previous: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "value", row: 0, text: "Value 1", width: 10)
          ]),
        current: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "value", row: 0, text: "Value 2", width: 10)
          ]),
        damage: .init(textRows: [.init(row: 0, columnRanges: [0..<10])])
      ),
      .init(
        name: "text shrink clears trailing cells",
        previous: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "shrinking", row: 0, text: "ABCD", width: 4)
          ]),
        current: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "shrinking", row: 0, text: "ABX", width: 4)
          ]),
        damage: .init(textRows: [.init(row: 0, columnRanges: [2..<4])])
      ),
      .init(
        name: "moved row clears old bounds and paints new bounds",
        previous: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "moving", row: 0, text: "MOVE", width: 6)
          ]),
        current: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "moving", row: 2, text: "MOVE", width: 6)
          ]),
        damage: .init(
          textRows: [
            .init(row: 0, columnRanges: [0..<6]),
            .init(row: 2, columnRanges: [0..<6]),
          ])
      ),
      .init(
        name: "clean sibling outside dirty rows is retained",
        previous: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "dirty", row: 0, text: "old", width: 6),
            coreRasterTextNode(id: "clean", row: 2, text: "keep", width: 6),
          ]),
        current: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "dirty", row: 0, text: "new", width: 6),
            coreRasterTextNode(id: "clean", row: 2, text: "keep", width: 6),
          ]),
        damage: .init(textRows: [.init(row: 0, columnRanges: [0..<6])])
      ),
      .init(
        name: "image attachment outside dirty rows is retained",
        previous: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "dirtyImageSibling", row: 0, text: "old", width: 6),
            coreRasterImageNode(id: "image", row: 2, source: "demo.png"),
          ]),
        current: coreRasterRoot(
          width: 12,
          height: 4,
          children: [
            coreRasterTextNode(id: "dirtyImageSibling", row: 0, text: "new", width: 6),
            coreRasterImageNode(id: "image", row: 2, source: "demo.png"),
          ]),
        damage: .init(textRows: [.init(row: 0, columnRanges: [0..<6])])
      ),
    ]

    for mutation in mutations {
      let previousSurface = rasterizer.rasterize(
        mutation.previous,
        minimumSize: mutation.minimumSize
      )
      let fresh = rasterizer.rasterize(
        mutation.current,
        minimumSize: mutation.minimumSize
      )
      let incremental = rasterizer.rasterize(
        mutation.current,
        minimumSize: mutation.minimumSize,
        previousSurface: previousSurface,
        damage: mutation.damage
      )

      #expect(
        incremental == fresh,
        "incremental repaint differed from fresh raster for \(mutation.name)"
      )
    }
  }

  @Test("default incremental verification falls back to fresh raster for incomplete damage")
  func defaultIncrementalVerificationFallsBackToFreshRasterForIncompleteDamage() {
    let rasterizer = Rasterizer()
    let minimumSize = CellSize(width: 6, height: 1)
    let previous = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "ABCD", width: 4)
      ])
    let current = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "AB", width: 4)
      ])

    let previousSurface = rasterizer.rasterize(previous, minimumSize: minimumSize)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: nil,
      damage: nil
    )
    let verified = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [2..<3])])
    )

    // The default policy is configuration-dependent by design (see
    // `defaultIncrementalVerificationPolicy()`): DEBUG verifies and repairs,
    // release trusts proven damage as-is (the sampled probe records the
    // mismatch instead of repairing). The release soundness lane runs this
    // test in release, so pin each configuration's contract.
    #if DEBUG
      #expect(verified.surface == fresh.surface)
      #expect(verified.presentationDamage == nil)
    #else
      #expect(verified.surface != fresh.surface)
      #expect(verified.presentationDamage != nil)
      #expect(verified.incrementalMismatch == nil)
    #endif
  }

  @Test("incremental mismatch fallback reports which rows diverged")
  func incrementalMismatchFallbackReportsDivergedRows() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let minimumSize = CellSize(width: 6, height: 1)
    let previous = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "ABCD", width: 4)
      ])
    let current = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "AB", width: 4)
      ])

    let previousSurface = rasterizer.rasterize(previous, minimumSize: minimumSize)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: nil,
      damage: nil
    )
    let verified = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [2..<3])])
    )

    // The repair still happens — but it may no longer happen in silence.
    #expect(verified.surface == fresh.surface)
    #expect(verified.incrementalMismatch != nil)
    #expect(verified.incrementalMismatch?.mismatchedRows == [0])
  }

  @Test("a sound incremental repaint reports no mismatch")
  func soundIncrementalRepaintReportsNoMismatch() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .verifySoundDamage)
    let minimumSize = CellSize(width: 6, height: 1)
    let previous = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "ABCD", width: 4)
      ])
    let current = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "AB", width: 4)
      ])

    let previousSurface = rasterizer.rasterize(previous, minimumSize: minimumSize)
    let sound = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [0..<6])])
    )

    #expect(sound.incrementalMismatch == nil)
  }

  @Test("trusted incremental raster policy skips fresh fallback for incomplete damage")
  func trustedIncrementalPolicySkipsFreshFallbackForIncompleteDamage() {
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)
    let minimumSize = CellSize(width: 6, height: 1)
    let previous = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "ABCD", width: 4)
      ])
    let current = coreRasterRoot(
      width: 6,
      height: 1,
      children: [
        coreRasterTextNode(id: "shrinking", row: 0, text: "AB", width: 4)
      ])

    let previousSurface = rasterizer.rasterize(previous, minimumSize: minimumSize)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: nil,
      damage: nil
    )
    let trusted = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: minimumSize,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [2..<3])])
    )

    #expect(trusted.surface != fresh.surface)
    #expect(trusted.presentationDamage != nil)
  }

  @Test("incremental raster reuse falls back to fresh raster for incompatible surface size")
  func incrementalRasterReuseFallsBackForIncompatibleSurfaceSize() {
    let rasterizer = Rasterizer()
    let previous = coreRasterRoot(
      width: 4,
      height: 1,
      children: [coreRasterTextNode(id: "row", row: 0, text: "OLD", width: 4)]
    )
    let current = coreRasterRoot(
      width: 5,
      height: 1,
      children: [coreRasterTextNode(id: "row", row: 0, text: "NEW", width: 5)]
    )
    let previousSurface = rasterizer.rasterize(previous, minimumSize: .zero)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 0, columnRanges: [0..<5])])
    )

    #expect(result.surface == fresh.surface)
    #expect(result.presentationDamage == nil)
  }

  @Test("incremental raster reuse falls back to fresh raster for empty damage rows")
  func incrementalRasterReuseFallsBackForEmptyDamageRows() {
    let rasterizer = Rasterizer()
    let previous = coreRasterRoot(
      children: [coreRasterTextNode(id: "row", row: 0, text: "OLD", width: 4)]
    )
    let current = coreRasterRoot(
      children: [coreRasterTextNode(id: "row", row: 0, text: "NEW", width: 4)]
    )
    let previousSurface = rasterizer.rasterize(previous, minimumSize: .zero)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [])
    )

    #expect(result.surface == fresh.surface)
    #expect(result.presentationDamage == nil)
  }

  @Test("incremental raster reuse falls back to fresh raster for full text repaint")
  func incrementalRasterReuseFallsBackForFullTextRepaint() {
    let rasterizer = Rasterizer()
    let previous = coreRasterRoot(
      children: [
        coreRasterTextNode(id: "dirty", row: 0, text: "A", width: 4),
        coreRasterTextNode(id: "missed", row: 1, text: "OLD", width: 4),
      ]
    )
    let current = coreRasterRoot(
      children: [
        coreRasterTextNode(id: "dirty", row: 0, text: "B", width: 4),
        coreRasterTextNode(id: "missed", row: 1, text: "NEW", width: 4),
      ]
    )
    let previousSurface = rasterizer.rasterize(previous, minimumSize: .zero)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(
        textRows: [.init(row: 0, columnRanges: [0..<4])],
        requiresFullTextRepaint: true
      )
    )

    #expect(result.surface == fresh.surface)
    #expect(result.presentationDamage == nil)
  }

  @Test("incremental raster reuse falls back to fresh raster for full graphics replay")
  func incrementalRasterReuseFallsBackForFullGraphicsReplay() {
    let rasterizer = Rasterizer()
    let previous = coreRasterRoot(
      children: [
        coreRasterTextNode(id: "dirty", row: 0, text: "A", width: 4),
        coreRasterImageNode(id: "image", row: 1, source: "old.png"),
      ]
    )
    let current = coreRasterRoot(
      children: [
        coreRasterTextNode(id: "dirty", row: 0, text: "B", width: 4),
        coreRasterImageNode(id: "image", row: 1, source: "new.png"),
      ]
    )
    let previousSurface = rasterizer.rasterize(previous, minimumSize: .zero)
    let fresh = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: nil,
      damage: nil
    )

    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      current,
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(
        textRows: [.init(row: 0, columnRanges: [0..<4])],
        requiresFullGraphicsReplay: true
      )
    )

    #expect(result.surface == fresh.surface)
    #expect(result.presentationDamage == nil)
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

private func imagePayload() -> ImagePayload {
  ImagePayload(
    source: .path("demo.png"),
    resolvedAsset: ResolvedImageAsset(
      reference: .filePath("/tmp/demo.png"),
      pixelSize: .init(width: 8, height: 16),
      intrinsicCellSize: .init(width: 1, height: 1),
      cellPixelSize: .init(width: 8, height: 16)
    )
  )
}

private func layerContentKind(_ layer: RasterPresentationLayer) -> String {
  switch layer.content {
  case .cells:
    return "cells"
  case .image:
    return "image"
  }
}

private func imageAttachment(
  in layer: RasterPresentationLayer
) -> RasterImageAttachment? {
  if case .image(let attachment) = layer.content {
    return attachment
  }
  return nil
}

private func cellFragment(
  in layer: RasterPresentationLayer
) -> RasterSurfaceFragment? {
  if case .cells(let fragment) = layer.content {
    return fragment
  }
  return nil
}

private struct CoreRasterRepaintMutation {
  var name: String
  var previous: DrawNode
  var current: DrawNode
  var damage: PresentationDamage
  var minimumSize = CellSize(width: 12, height: 4)
}

private func coreRasterRoot(
  width: Int = 6,
  height: Int = 3,
  children: [DrawNode]
) -> DrawNode {
  DrawNode(
    identity: testIdentity("RasterizerFallbackRoot"),
    bounds: .init(origin: .zero, size: .init(width: width, height: height)),
    children: children
  )
}

private func coreRasterTextNode(
  id: String,
  row: Int,
  text: String,
  width: Int
) -> DrawNode {
  let bounds = CellRect(
    origin: .init(x: 0, y: row),
    size: .init(width: width, height: 1)
  )
  return DrawNode(
    identity: testIdentity("RasterizerFallback", id),
    bounds: bounds,
    commands: [
      .text(
        bounds: bounds,
        content: text,
        style: .init(),
        lineLimit: nil,
        truncationMode: .tail,
        wrappingStrategy: .wordBoundary
      )
    ]
  )
}

private func coreRasterImageNode(
  id: String,
  row: Int,
  source: String
) -> DrawNode {
  let bounds = CellRect(
    origin: .init(x: 0, y: row),
    size: .init(width: 4, height: 1)
  )
  let identity = testIdentity("RasterizerFallback", id)
  return DrawNode(
    identity: identity,
    bounds: bounds,
    commands: [
      .image(
        bounds: bounds,
        identity: identity,
        payload: .init(source: .path(source))
      )
    ]
  )
}

private func fillNode(
  _ id: String,
  bounds: CellRect,
  color: Color,
  drawEffects: DrawEffects = .init()
) -> DrawNode {
  DrawNode(
    identity: testIdentity("RasterizerFill", id),
    bounds: bounds,
    drawEffects: drawEffects,
    commands: [fillCommand(bounds: bounds, color: color)]
  )
}

private func fillCommand(
  bounds: CellRect,
  color: Color
) -> DrawCommand {
  .fill(
    bounds: bounds,
    geometry: .rectangle,
    insetAmount: 0,
    style: .color(color),
    mode: .full
  )
}

private func expectColor(
  _ actual: Color?,
  equals expected: Color,
  tolerance: Double = 0.0001
) {
  guard let actual else {
    Issue.record("expected color \(expected), got nil")
    return
  }
  #expect(abs(actual.red - expected.red) < tolerance)
  #expect(abs(actual.green - expected.green) < tolerance)
  #expect(abs(actual.blue - expected.blue) < tolerance)
  #expect(abs(actual.alpha - expected.alpha) < tolerance)
}
