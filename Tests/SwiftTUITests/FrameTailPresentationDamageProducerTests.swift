import SwiftTUICore
import Testing

@testable import SwiftTUIRuntime

/// F07: the incremental damage *producer* must cover where an invalidated
/// subtree actually paints, not just the invalidated node's own slot.
///
/// `.offset`/`.position` bake their translation into the *child's* absolute
/// bounds while the wrapper keeps its own slot, so deriving damage rows from
/// the invalidated wrapper's `bounds` misses every row the translated subtree
/// paints — under release's `.trustSoundDamage` policy that shipped as a
/// persistent ghost trail (DEBUG's verify policy silently repaired it; see the
/// F06 mismatch counter). The consumer-side cull fix (`e552ad98`) cannot help:
/// rows the producer never marks dirty are never repainted at all.
@MainActor
@Suite("Frame tail presentation damage producer")
struct FrameTailPresentationDamageProducerTests {
  @Test("an invalidated offset wrapper damages the rows its subtree paints")
  func invalidatedOffsetWrapperDamagesSubtreeRows() {
    let rootIdentity = testIdentity()
    let wrapperIdentity = testIdentity("Wrapper")
    let contentIdentity = testIdentity("Wrapper", "Content")

    // The wrapper occupies its layout slot on row 1; its offset child paints
    // far outside that slot (row 10 previously, row 12 currently).
    let previousPlaced = placedTree(
      rootIdentity: rootIdentity,
      wrapperIdentity: wrapperIdentity,
      contentIdentity: contentIdentity,
      contentRow: 10
    )
    let currentPlaced = placedTree(
      rootIdentity: rootIdentity,
      wrapperIdentity: wrapperIdentity,
      contentIdentity: contentIdentity,
      contentRow: 12
    )

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: currentPlaced,
      draw: drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: frameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [wrapperIdentity]
      ),
      previousDraw: drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    let dirtyRows = plan.damage?.dirtyRows ?? []
    #expect(dirtyRows.contains(10), "the subtree's previous rows must be erased")
    #expect(dirtyRows.contains(12), "the subtree's current rows must be painted")
    // The wrapper's own slot (row 1) is deliberately NOT damaged: the wrapper's
    // own paint projection is unchanged between the two frames, and the
    // placed-tree diff damages what changed rather than the invalidated node's
    // whole subtree. Damaging it was the seed-set producer's over-approximation.
    #expect(!dirtyRows.contains(1))
  }

  @Test("a contained invalidated subtree damages exactly its own rows")
  func containedInvalidatedSubtreeKeepsMinimalDamage() {
    let rootIdentity = testIdentity()
    let wrapperIdentity = testIdentity("Wrapper")
    let contentIdentity = testIdentity("Wrapper", "Content")

    // Content sits inside the wrapper's slot, and only its width changes, so
    // the producer must not widen damage past the row it paints and its
    // one-cell half-block margin.
    let previousPlaced = placedTree(
      rootIdentity: rootIdentity,
      wrapperIdentity: wrapperIdentity,
      contentIdentity: contentIdentity,
      contentRow: 1
    )
    let currentPlaced = placedTree(
      rootIdentity: rootIdentity,
      wrapperIdentity: wrapperIdentity,
      contentIdentity: contentIdentity,
      contentRow: 1,
      contentWidth: 12
    )

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: currentPlaced,
      draw: drawTree(from: currentPlaced),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: frameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [wrapperIdentity]
      ),
      previousDraw: drawTree(from: previousPlaced),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    #expect(plan.damage?.dirtyRows == [0, 1, 2])
  }

  @Test("a foreign surface whose grid changes at the same bounds damages its rows")
  func foreignSurfaceGridChangeDamagesItsRows() {
    let rootIdentity = testIdentity()
    let labelIdentity = testIdentity("Label")
    let surfaceIdentity = testIdentity("Surface")
    let labelBounds = CellRect(origin: .zero, size: .init(width: 20, height: 1))
    let surfaceBounds = CellRect(origin: .init(x: 0, y: 4), size: .init(width: 2, height: 1))
    let placed = PlacedNode(
      identity: rootIdentity,
      kind: .root,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 6)),
      children: [
        PlacedNode(identity: labelIdentity, kind: .view("Text"), bounds: labelBounds),
        PlacedNode(identity: surfaceIdentity, kind: .view("ForeignSurface"), bounds: surfaceBounds),
      ]
    )
    // The label is the invalidated node; the surface's grid changes alongside it.
    func draw(label: String, grid: String) -> DrawNode {
      DrawNode(
        identity: rootIdentity,
        bounds: placed.bounds,
        children: [
          DrawNode(
            identity: labelIdentity, bounds: labelBounds,
            commands: [.preformattedText(bounds: labelBounds, lines: [label], style: .init())]),
          DrawNode(
            identity: surfaceIdentity, bounds: surfaceBounds,
            commands: [
              .foreignSurface(
                bounds: surfaceBounds,
                payload: GridPayload(
                  grid: ForeignGrid(
                    size: surfaceBounds.size,
                    cells: [grid.map { RasterCell(character: $0) }])))
            ]),
        ]
      )
    }

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: placed,
      draw: draw(label: "after", grid: "CD"),
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(frame: frameArtifacts(placed: placed)),
        invalidatedIdentities: [labelIdentity]
      ),
      previousDraw: draw(label: "before", grid: "AB"),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: placed)
    )

    #expect(plan.barriers.isEmpty)
    #expect(plan.damage?.dirtyRows == [0, 1, 3, 4, 5])
  }

  private func placedTree(
    rootIdentity: Identity,
    wrapperIdentity: Identity,
    contentIdentity: Identity,
    contentRow: Int,
    contentWidth: Int = 20
  ) -> PlacedNode {
    PlacedNode(
      identity: rootIdentity,
      kind: .root,
      bounds: .init(origin: .zero, size: .init(width: 20, height: 3)),
      children: [
        PlacedNode(
          identity: wrapperIdentity,
          kind: .view("Offset"),
          bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 20, height: 1)),
          children: [
            PlacedNode(
              identity: contentIdentity,
              kind: .view("Text"),
              bounds: .init(
                origin: .init(x: 0, y: contentRow),
                size: .init(width: contentWidth, height: 1)
              )
            )
          ]
        )
      ]
    )
  }

  private func frameArtifacts(placed: PlacedNode) -> FrameArtifacts {
    FrameArtifacts(
      resolvedTree: resolvedTree(from: placed),
      measuredTree: measuredTree(from: placed),
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: drawTree(from: placed),
      rasterSurface: .init(),
      presentationDamage: nil,
      drawnIdentities: [],
      commitPlan: .init()
    )
  }

  private func resolvedTree(from node: PlacedNode) -> ResolvedNode {
    ResolvedNode(
      identity: node.identity,
      kind: node.kind,
      children: node.children.map(resolvedTree(from:))
    )
  }

  private func measuredTree(from node: PlacedNode) -> MeasuredNode {
    MeasuredNode(
      identity: node.identity,
      proposal: .unspecified,
      measuredSize: .zero,
      childMeasurements: node.children.map(measuredTree(from:))
    )
  }

  private func drawTree(from node: PlacedNode) -> DrawNode {
    DrawNode(
      identity: node.identity,
      bounds: node.bounds,
      children: node.children.map(drawTree(from:))
    )
  }
}

private struct GridPayload: ForeignSurfacePayload {
  let grid: ForeignGrid
}
