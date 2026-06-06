import Testing

@testable import SwiftTUICore

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
