import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

@Suite(.serialized)
struct FrameworkStressKittyPlacementGeometryTests {
  @Test("stress kitty placement geometry 001 unclipped placement preserves logical bounds")
  func kittyPlacement001UnclippedPlacementPreservesLogicalBounds() throws {
    // Hypothesis: the default visible-bounds projection can manufacture a source crop.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 3, y: 4), size: .init(width: 8, height: 6))
    )
    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 80, height: 60))
    )

    #expect(placement.origin == CellPoint(x: 3, y: 4))
    #expect(placement.cellColumns == 8)
    #expect(placement.cellRows == 6)
    #expect(placement.sourceRect == nil)
  }

  @Test("stress kitty placement geometry 002 leading edge clips map proportionally")
  func kittyPlacement002LeadingEdgeClipsMapProportionally() throws {
    // Hypothesis: simultaneous top and left clips can reuse one axis's pixel offset.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 2, y: 3), size: .init(width: 10, height: 8)),
      visibleBounds: .init(origin: .init(x: 4, y: 5), size: .init(width: 8, height: 6))
    )
    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 80))
    )

    #expect(placement.origin == CellPoint(x: 4, y: 5))
    #expect(placement.cellColumns == 8)
    #expect(placement.cellRows == 6)
    #expect(placement.sourceRect == KittySourceRect(x: 20, y: 20, width: 80, height: 60))
  }

  @Test("stress kitty placement geometry 003 trailing edge clips preserve asymmetric crop")
  func kittyPlacement003TrailingEdgeClipsPreserveAsymmetricCrop() throws {
    // Hypothesis: right and bottom trims can be applied to the origin instead of the extent.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 2, y: 3), size: .init(width: 10, height: 8)),
      visibleBounds: .init(origin: .init(x: 2, y: 3), size: .init(width: 7, height: 5))
    )
    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 80))
    )

    #expect(placement.origin == CellPoint(x: 2, y: 3))
    #expect(placement.cellColumns == 7)
    #expect(placement.cellRows == 5)
    #expect(placement.sourceRect == KittySourceRect(x: 0, y: 0, width: 70, height: 50))
  }

  @Test("stress kitty placement geometry 004 visibility wholly right produces no placement")
  func kittyPlacement004VisibilityWhollyRightProducesNoPlacement() {
    // Hypothesis: max-one clamping can turn a disjoint right-side clip into a phantom cell.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .zero, size: .init(width: 4, height: 4)),
      visibleBounds: .init(origin: .init(x: 8, y: 0), size: .init(width: 2, height: 4))
    )

    withKnownIssue("A disjoint right-side Kitty clip becomes a phantom one-cell placement") {
      #expect(
        kittyPlacement(for: attachment, imagePixelSize: .init(width: 40, height: 40))
          == nil
      )
    }
  }

  @Test("stress kitty placement geometry 005 visibility wholly left produces no placement")
  func kittyPlacement005VisibilityWhollyLeftProducesNoPlacement() {
    // Hypothesis: a disjoint left-side clip can retain the logical origin as one visible column.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 8, y: 0), size: .init(width: 4, height: 4)),
      visibleBounds: .init(origin: .zero, size: .init(width: 2, height: 4))
    )

    withKnownIssue("A disjoint left-side Kitty clip becomes a phantom one-cell placement") {
      #expect(
        kittyPlacement(for: attachment, imagePixelSize: .init(width: 40, height: 40))
          == nil
      )
    }
  }

  @Test("stress kitty placement geometry 006 visibility wholly below produces no placement")
  func kittyPlacement006VisibilityWhollyBelowProducesNoPlacement() {
    // Hypothesis: max-one row clamping can resurrect a vertically disjoint image.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .zero, size: .init(width: 4, height: 4)),
      visibleBounds: .init(origin: .init(x: 0, y: 8), size: .init(width: 4, height: 2))
    )

    withKnownIssue("A disjoint lower Kitty clip becomes a phantom one-cell placement") {
      #expect(
        kittyPlacement(for: attachment, imagePixelSize: .init(width: 40, height: 40))
          == nil
      )
    }
  }

  @Test("stress kitty placement geometry 007 visibility wholly above produces no placement")
  func kittyPlacement007VisibilityWhollyAboveProducesNoPlacement() {
    // Hypothesis: a disjoint upper clip can retain one row at the logical origin.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 0, y: 8), size: .init(width: 4, height: 4)),
      visibleBounds: .init(origin: .zero, size: .init(width: 4, height: 2))
    )

    withKnownIssue("A disjoint upper Kitty clip becomes a phantom one-cell placement") {
      #expect(
        kittyPlacement(for: attachment, imagePixelSize: .init(width: 40, height: 40))
          == nil
      )
    }
  }

  @Test("stress kitty placement geometry 008 oversized visibility stays within logical bounds")
  func kittyPlacement008OversizedVisibilityStaysWithinLogicalBounds() throws {
    // Hypothesis: an ancestor clip larger than the image can expand its terminal placement.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .init(x: 5, y: 5), size: .init(width: 4, height: 3)),
      visibleBounds: .init(origin: .zero, size: .init(width: 20, height: 20))
    )
    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 40, height: 30))
    )

    #expect(placement.origin == CellPoint(x: 5, y: 5))
    #expect(placement.cellColumns == 4)
    #expect(placement.cellRows == 3)
    #expect(placement.sourceRect == nil)
  }

  @Test("stress kitty placement geometry 009 one cell corner overlap keeps exact source corner")
  func kittyPlacement009OneCellCornerOverlapKeepsExactSourceCorner() throws {
    // Hypothesis: simultaneous near-total clips can round the final source pixel region away.
    let attachment = kittyGeometryAttachment(
      bounds: .init(origin: .zero, size: .init(width: 10, height: 10)),
      visibleBounds: .init(origin: .init(x: 9, y: 9), size: .init(width: 5, height: 5))
    )
    let placement = try #require(
      kittyPlacement(for: attachment, imagePixelSize: .init(width: 100, height: 100))
    )

    #expect(placement.origin == CellPoint(x: 9, y: 9))
    #expect(placement.cellColumns == 1)
    #expect(placement.cellRows == 1)
    #expect(placement.sourceRect == KittySourceRect(x: 90, y: 90, width: 10, height: 10))
  }
}

private func kittyGeometryAttachment(
  bounds: CellRect,
  visibleBounds: CellRect? = nil
) -> RasterImageAttachment {
  RasterImageAttachment(
    identity: testIdentity("KittyPlacementGeometry"),
    bounds: bounds,
    visibleBounds: visibleBounds,
    source: .data([]),
    resolvedReference: .embeddedImage([]),
    pixelSize: .init(width: 1, height: 1),
    isResizable: false,
    scalingMode: .stretch
  )
}
