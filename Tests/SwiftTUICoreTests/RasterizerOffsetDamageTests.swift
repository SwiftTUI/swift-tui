import Testing

@testable import SwiftTUICore

/// Regression for the incremental-repaint dirty-row cull dropping `.offset`
/// descendants.
///
/// `.offset`/`.position` bake their translation into the *child's* absolute
/// bounds while the wrapper keeps its own slot. The incremental paint walk used
/// to cull a subtree when the node's *own* bounds fell outside the dirty-row
/// band — so when only an offset child's rows were dirty, the wrapper (still at
/// its slot) was culled before the child was reached, and the cleared rows
/// stayed blank/stale. In release (`.trustSoundDamage`) that shipped as silent
/// visual corruption; DEBUG's `.verifySoundDamage` masked it with a fresh-raster
/// fallback. The cull now tests the subtree's absolute extent (`subtreeBounds`).
@MainActor
@Suite("Incremental raster offset-descendant damage")
struct RasterizerOffsetDamageTests {
  private let wrapperBounds = CellRect(
    origin: .init(x: 0, y: 0),
    size: .init(width: 3, height: 1)
  )
  private let childBounds = CellRect(
    origin: .init(x: 0, y: 10),
    size: .init(width: 3, height: 1)
  )

  private func offsetTree(childText: String) -> DrawNode {
    DrawNode(
      identity: testIdentity("offset-wrapper"),
      bounds: wrapperBounds,  // the slot stays at row 0
      children: [
        DrawNode(
          identity: testIdentity("offset-wrapper", "child"),
          bounds: childBounds,  // `.offset` baked the translation to row 10
          commands: [
            .text(
              bounds: childBounds,
              content: childText,
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

  @Test("an offset child whose rows are dirty repaints though its wrapper slot is outside the band")
  func offsetDescendantRepaintsUnderTrustedDamage() {
    // `.trustSoundDamage` mirrors release: no fresh-raster fallback that would
    // paper over an incomplete incremental paint.
    let rasterizer = Rasterizer(incrementalVerificationPolicy: .trustSoundDamage)

    let previousSurface = rasterizer.rasterize(offsetTree(childText: "OLD"))
    #expect(previousSurface.lines.count == 11)
    #expect(previousSurface.lines[10] == "OLD")

    // Only the offset child's row (10) is dirty; the wrapper's slot row (0) is not.
    let result = rasterizer.rasterizeCollectingVisibleIdentities(
      offsetTree(childText: "NEW"),
      minimumSize: .zero,
      previousSurface: previousSurface,
      damage: .init(textRows: [.init(row: 10, columnRanges: [0..<3])])
    )

    // Before the fix the wrapper was culled on its own row-0 bounds, so the
    // offset child never repainted and row 10 stayed "OLD" (or blank).
    #expect(result.surface.lines[10] == "NEW")
  }

  @Test(
    "subtreeBounds encloses a translated offset descendant but is unchanged for contained children")
  func subtreeBoundsAggregation() {
    let offsetWrapper = offsetTree(childText: "X")
    // The wrapper's own bounds are row 0; subtreeBounds must reach the offset
    // child at row 10 (rows 0..<11).
    #expect(
      offsetWrapper.subtreeBounds
        == CellRect(origin: .init(x: 0, y: 0), size: .init(width: 3, height: 11))
    )

    // A contained child leaves subtreeBounds equal to the node's own bounds, so
    // the cull behaves identically to before for ordinary layouts.
    let containedParentBounds = CellRect(
      origin: .init(x: 0, y: 0),
      size: .init(width: 10, height: 5)
    )
    let contained = DrawNode(
      identity: testIdentity("parent"),
      bounds: containedParentBounds,
      children: [
        DrawNode(
          identity: testIdentity("parent", "child"),
          bounds: CellRect(origin: .init(x: 1, y: 1), size: .init(width: 2, height: 2))
        )
      ]
    )
    #expect(contained.subtreeBounds == containedParentBounds)
  }
}
