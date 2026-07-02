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
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: frameArtifacts(placed: previousPlaced)
        ),
        invalidatedIdentities: [wrapperIdentity]
      ),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: previousPlaced)
    )

    #expect(plan.barriers.isEmpty)
    let dirtyRows = plan.damage?.dirtyRows ?? []
    #expect(dirtyRows.contains(1), "the wrapper's own slot must stay damaged")
    #expect(dirtyRows.contains(10), "the subtree's previous rows must be erased")
    #expect(dirtyRows.contains(12), "the subtree's current rows must be painted")
  }

  @Test("a contained invalidated subtree damages exactly its own rows")
  func containedInvalidatedSubtreeKeepsMinimalDamage() {
    let rootIdentity = testIdentity()
    let wrapperIdentity = testIdentity("Wrapper")
    let contentIdentity = testIdentity("Wrapper", "Content")

    // Content sits inside the wrapper's slot: subtree extent == own bounds,
    // so the subtree-aware producer must not widen damage at all.
    let placed = placedTree(
      rootIdentity: rootIdentity,
      wrapperIdentity: wrapperIdentity,
      contentIdentity: contentIdentity,
      contentRow: 1
    )

    let plan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: rootIdentity,
      placed: placed,
      retainedLayout: RetainedLayoutSession(
        previousFrameIndex: RetainedFrameIndex(
          frame: frameArtifacts(placed: placed)
        ),
        invalidatedIdentities: [wrapperIdentity]
      ),
      previousSurfaceTopology: SurfaceTopologySignature(placedRoot: placed)
    )

    #expect(plan.barriers.isEmpty)
    #expect(plan.damage?.dirtyRows == [1])
  }

  private func placedTree(
    rootIdentity: Identity,
    wrapperIdentity: Identity,
    contentIdentity: Identity,
    contentRow: Int
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
                size: .init(width: 20, height: 1)
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
