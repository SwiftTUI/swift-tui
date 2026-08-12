import SwiftTUITestSupport
import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Kitty placements draw above every text cell, so the placement geometry
/// must honor the raster-time occlusion trim: an image partially covered by
/// later-painted cells (a command palette, a sheet) is cropped to its
/// unoccluded rect, and a fully covered image produces no placement at all.
@Suite
struct TerminalImageOcclusionPlacementTests {
  @Test("occlusion trim crops the placement and its source rect")
  func occlusionTrimCropsPlacement() throws {
    var attachment = occlusionPlacementAttachment(
      bounds: .init(origin: .zero, size: .init(width: 10, height: 8))
    )
    attachment.unoccludedVisibleBounds = CellRect(
      origin: .zero, size: .init(width: 10, height: 4))

    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 80))
    )

    #expect(placement.origin == CellPoint(x: 0, y: 0))
    #expect(placement.cellColumns == 10)
    #expect(placement.cellRows == 4)
    #expect(placement.sourceRect == KittySourceRect(x: 0, y: 0, width: 100, height: 40))
  }

  @Test("occlusion trim composes with the ancestor clip")
  func occlusionTrimComposesWithAncestorClip() throws {
    var attachment = occlusionPlacementAttachment(
      bounds: .init(origin: .init(x: 2, y: 2), size: .init(width: 10, height: 8)),
      visibleBounds: .init(origin: .init(x: 2, y: 4), size: .init(width: 10, height: 6))
    )
    // A presentation covers the clipped rect's bottom two rows.
    attachment.unoccludedVisibleBounds = CellRect(
      origin: .init(x: 2, y: 4), size: .init(width: 10, height: 4))

    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 80))
    )

    #expect(placement.origin == CellPoint(x: 2, y: 4))
    #expect(placement.cellColumns == 10)
    #expect(placement.cellRows == 4)
    #expect(placement.sourceRect == KittySourceRect(x: 0, y: 20, width: 100, height: 40))
  }

  @Test("a fully occluded attachment produces no placement")
  func fullyOccludedAttachmentProducesNoPlacement() {
    var attachment = occlusionPlacementAttachment(
      bounds: .init(origin: .zero, size: .init(width: 10, height: 8))
    )
    attachment.unoccludedVisibleBounds = CellRect(origin: .zero, size: .zero)

    #expect(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 80))
        == nil
    )
  }
}

private func occlusionPlacementAttachment(
  bounds: CellRect,
  visibleBounds: CellRect? = nil
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: testIdentity("ImageOcclusionPlacement"),
    bounds: bounds,
    visibleBounds: visibleBounds,
    source: .data([]),
    resolvedReference: .embeddedImage([]),
    pixelSize: .init(width: 1, height: 1),
    isResizable: false,
    scalingMode: .stretch
  )
}
