import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct RasterSurfaceDamageDiffTests {
  @Test("diff returns nil when there is no previous surface")
  func diffReturnsNilWithoutPreviousSurface() {
    let current = RasterSurface(size: .init(width: 4, height: 1), lines: ["ABCD"])

    #expect(RasterSurfaceDamageDiff.diff(previous: nil, current: current) == nil)
  }

  @Test("diff returns empty damage when compatible surfaces are visually equal")
  func diffReturnsEmptyDamageForEqualSurfaces() {
    let surface = RasterSurface(size: .init(width: 4, height: 1), lines: ["ABCD"])

    #expect(
      RasterSurfaceDamageDiff.diff(previous: surface, current: surface)
        == PresentationDamage(textRows: [])
    )
  }

  @Test("diff coalesces adjacent changed cells into row ranges")
  func diffCoalescesAdjacentChangedCells() {
    let previous = RasterSurface(size: .init(width: 6, height: 2), lines: ["ABCDEF", "stable"])
    let current = RasterSurface(size: .init(width: 6, height: 2), lines: ["ABxyEF", "stable"])

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 0, columnRanges: [2..<4])
        ])
    )
  }

  @Test("diff tracks style-only cell changes")
  func diffTracksStyleOnlyCellChanges() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["ABCD"])
    let current = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["ABCD"],
      styleRuns: [
        .init(x: 1, y: 0, length: 2, style: TextStyle(emphasis: .bold))
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 0, columnRanges: [1..<3])
        ])
    )
  }

  @Test("diff expands wide glyph changes to the full occupied cell range")
  func diffExpandsWideGlyphChanges() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["A界B"])
    let current = RasterSurface(size: .init(width: 4, height: 1), lines: ["A語B"])

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 0, columnRanges: [1..<3])
        ])
    )
  }

  @Test("diff falls back to full repaint when size or metadata changes")
  func diffFallsBackForIncompatibleSurfaces() {
    let previous = RasterSurface(size: .init(width: 4, height: 1), lines: ["ABCD"])
    let resized = RasterSurface(size: .init(width: 5, height: 1), lines: ["ABCDE"])
    let metadataChanged = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["ABCD"],
      metadata: ["mode": "alternate"]
    )

    #expect(RasterSurfaceDamageDiff.diff(previous: previous, current: resized) == nil)
    #expect(RasterSurfaceDamageDiff.diff(previous: previous, current: metadataChanged) == nil)
  }

  @Test("diff marks previous and current image rows dirty")
  func diffMarksImageRowsDirty() {
    let identity = Identity(components: ["image"])
    let previous = RasterSurface(
      size: .init(width: 8, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: .init(origin: .init(x: 1, y: 1), size: .init(width: 2, height: 2)),
          source: .path("old.png")
        )
      ]
    )
    let current = RasterSurface(
      size: .init(width: 8, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: .init(origin: .init(x: 4, y: 2), size: .init(width: 2, height: 1)),
          source: .path("new.png")
        )
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 1, columnRanges: [1..<3]),
          .init(row: 2, columnRanges: [1..<3, 4..<6]),
        ])
    )
  }

  @Test("diff marks blended image rows dirty when only backdrop compositing changes")
  func diffMarksBlendedImageRowsDirtyWhenOnlyBackdropCompositingChanges() {
    let identity = Identity(components: ["image"])
    let bounds = CellRect(origin: .init(x: 1, y: 1), size: .init(width: 2, height: 2))
    let previous = RasterSurface(
      size: .init(width: 5, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          source: .path("image.png"),
          resolvedReference: .filePath("/tmp/image.png"),
          pixelSize: .init(width: 16, height: 32),
          cellPixelSize: .init(width: 8, height: 16),
          compositing: imageCompositing(signature: 1, background: .red, bounds: bounds)
        )
      ]
    )
    let current = RasterSurface(
      size: .init(width: 5, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          source: .path("image.png"),
          resolvedReference: .filePath("/tmp/image.png"),
          pixelSize: .init(width: 16, height: 32),
          cellPixelSize: .init(width: 8, height: 16),
          compositing: imageCompositing(signature: 2, background: .blue, bounds: bounds)
        )
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 1, columnRanges: [1..<3]),
          .init(row: 2, columnRanges: [1..<3]),
        ])
    )
  }

  @Test("diff marks blended image rows dirty when backdrop glyph foreground changes")
  func diffMarksBlendedImageRowsDirtyWhenBackdropGlyphForegroundChanges() {
    let identity = Identity(components: ["image"])
    let bounds = CellRect(origin: .init(x: 1, y: 1), size: .init(width: 2, height: 2))
    let previous = RasterSurface(
      size: .init(width: 5, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          source: .path("image.png"),
          resolvedReference: .filePath("/tmp/image.png"),
          pixelSize: .init(width: 16, height: 32),
          cellPixelSize: .init(width: 8, height: 16),
          compositing: imageCompositing(
            signature: 1,
            background: nil,
            foreground: .red,
            glyph: "A",
            bounds: bounds
          )
        )
      ]
    )
    let current = RasterSurface(
      size: .init(width: 5, height: 4),
      lines: ["", "", "", ""],
      imageAttachments: [
        RasterImageAttachment(
          identity: identity,
          bounds: bounds,
          source: .path("image.png"),
          resolvedReference: .filePath("/tmp/image.png"),
          pixelSize: .init(width: 16, height: 32),
          cellPixelSize: .init(width: 8, height: 16),
          compositing: imageCompositing(
            signature: 2,
            background: nil,
            foreground: .green,
            glyph: "B",
            bounds: bounds
          )
        )
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 1, columnRanges: [1..<3]),
          .init(row: 2, columnRanges: [1..<3]),
        ])
    )
  }

  @Test("diff ignores plain cell layer topology churn")
  func diffIgnoresPlainCellLayerTopologyChurn() {
    // Incremental rasterization re-mints order numbers and regroups plain cell
    // fragments every frame. Their content is fully represented in the cell
    // grid (compared cell by cell above), so sidecar churn alone must not
    // produce damage — including it unioned every glyph's bounds into damage
    // on each incremental frame (F36).
    let previous = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["ABCD"],
      presentationLayers: [
        cellLayer(order: 0, x: 0, width: 2),
        cellLayer(order: 1, x: 2, width: 2),
      ]
    )
    let current = RasterSurface(
      size: .init(width: 4, height: 1),
      lines: ["ABCD"],
      presentationLayers: [
        cellLayer(order: 5, x: 0, width: 4)
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [])
    )
  }

  @Test("diff ignores order renumbering of compositing-significant layers")
  func diffIgnoresOrderRenumberingOfSignificantLayers() {
    let identity = Identity(components: ["layer-image"])
    let bounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let image = RasterImageAttachment(
      identity: identity,
      bounds: bounds,
      source: .path("image.png")
    )
    let previous = RasterSurface(
      size: .init(width: 1, height: 1),
      lines: ["A"],
      imageAttachments: [image],
      presentationLayers: [
        RasterPresentationLayer(order: 0, bounds: bounds, content: .image(image)),
        cellLayer(order: 1, x: 0, width: 1),
      ]
    )
    let current = RasterSurface(
      size: .init(width: 1, height: 1),
      lines: ["A"],
      imageAttachments: [image],
      presentationLayers: [
        RasterPresentationLayer(order: 7, bounds: bounds, content: .image(image)),
        cellLayer(order: 9, x: 0, width: 1),
      ]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [])
    )
  }

  @Test("diff bounds effect-layer topology changes to the affected layers")
  func diffBoundsEffectLayerTopologyChangesToAffectedLayers() {
    let effectBounds = CellRect(origin: .init(x: 0, y: 1), size: .init(width: 2, height: 1))
    let previous = RasterSurface(
      size: .init(width: 4, height: 3),
      lines: ["aaaa", "bbbb", "cccc"],
      presentationLayers: [
        cellLayer(order: 0, x: 0, width: 4),
        cellLayer(order: 1, x: 0, width: 4, y: 1),
        cellLayer(order: 2, x: 0, width: 4, y: 2),
      ]
    )
    let current = RasterSurface(
      size: .init(width: 4, height: 3),
      lines: ["aaaa", "bbbb", "cccc"],
      presentationLayers: [
        cellLayer(order: 0, x: 0, width: 4),
        RasterPresentationLayer(
          order: 1,
          bounds: effectBounds,
          content: .cells(RasterSurfaceFragment(bounds: effectBounds, cells: [])),
          effects: [.blendMode(.screen)]
        ),
        cellLayer(order: 2, x: 0, width: 4, y: 2),
      ]
    )

    // The blended fragment appearing is a topology change, but the damage is
    // its own bounds — not the union of every layer on the surface.
    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 1, columnRanges: [0..<2])
        ])
    )
  }

  @Test("diff marks rows dirty when significant layer stacking changes")
  func diffMarksRowsDirtyWhenSignificantLayerStackingChanges() {
    let identity = Identity(components: ["layer-image"])
    let imageBounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
    let effectBounds = CellRect(origin: .init(x: 2, y: 0), size: .init(width: 1, height: 1))
    let image = RasterImageAttachment(
      identity: identity,
      bounds: imageBounds,
      source: .path("image.png")
    )
    let effectLayer = RasterPresentationLayer(
      order: 0,
      bounds: effectBounds,
      content: .cells(RasterSurfaceFragment(bounds: effectBounds, cells: [])),
      effects: [.blendMode(.multiply)]
    )
    let imageLayer = RasterPresentationLayer(
      order: 1,
      bounds: imageBounds,
      content: .image(image)
    )
    let previous = RasterSurface(
      size: .init(width: 3, height: 1),
      lines: ["ABC"],
      imageAttachments: [image],
      presentationLayers: [effectLayer, imageLayer]
    )
    let current = RasterSurface(
      size: .init(width: 3, height: 1),
      lines: ["ABC"],
      imageAttachments: [image],
      presentationLayers: [imageLayer, effectLayer]
    )

    #expect(
      RasterSurfaceDamageDiff.diff(previous: previous, current: current)
        == PresentationDamage(textRows: [
          .init(row: 0, columnRanges: [2..<3, 0..<1, 0..<1, 2..<3])
        ])
    )
  }
}

private func cellLayer(
  order: Int,
  x: Int,
  width: Int,
  y: Int = 0
) -> RasterPresentationLayer {
  let bounds = CellRect(
    origin: .init(x: x, y: y),
    size: .init(width: width, height: 1)
  )
  return RasterPresentationLayer(
    order: order,
    bounds: bounds,
    content: .cells(RasterSurfaceFragment(bounds: bounds, cells: []))
  )
}

private func imageCompositing(
  signature: UInt64,
  background: Color?,
  foreground: Color? = nil,
  glyph: Character? = nil,
  bounds: CellRect
) -> RasterImageCompositing {
  RasterImageCompositing(
    blendMode: .multiply,
    destinationBackdrop: RasterImageBackdrop(
      bounds: bounds,
      cells: Array(
        repeating: RasterImageBackdropCell(
          backgroundColor: background,
          foregroundColor: foreground,
          glyph: glyph
        ),
        count: bounds.size.width * bounds.size.height
      )
    ),
    cellPixelSize: .init(width: 8, height: 16),
    backdropSignature: signature
  )
}
