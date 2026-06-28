import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIRuntime

/// Regression for the retained phase-product gate (P1/P2).
///
/// `storeCommittedFrame` retains the committed frame's draw/semantic products so
/// the next frame can reuse them. It used to build a whole-tree extraction
/// signature for *both* the effective and baseline placed trees and keep the
/// products only when the two signatures matched — discarding them entirely when
/// the tree contained any node that does not support retained phase extraction
/// (a `.canvas`/custom layout), which starved the per-subtree partial-reuse path
/// tree-wide. It now compares the trees directly (the overlay-empty proxy, no
/// signature allocation) and stores the products with an *optional* signature, so
/// a canvas tree still feeds partial reuse while only the whole-tree fast path is
/// disabled.
@Suite("Retained phase-product gate")
struct RetainedPhaseProductGateTests {
  private struct Dots: CanvasDrawing, Equatable {
    func draw(into context: inout CanvasContext) {
      context.setSample(GridSample(x: 0, y: 0))
    }
  }

  private func artifacts(placed: PlacedNode, draw: DrawNode) -> FrameArtifacts {
    FrameArtifacts(
      resolvedTree: ResolvedNode(identity: placed.identity, kind: .root),
      measuredTree: MeasuredNode(
        identity: placed.identity,
        proposal: .unspecified,
        measuredSize: .zero
      ),
      placedTree: placed,
      semanticSnapshot: .init(),
      drawTree: draw,
      rasterSurface: .init(),
      commitPlan: CommitPlan(
        transaction: .init(),
        semanticSnapshot: .init(),
        lifecycle: [],
        handlerInstallations: []
      )
    )
  }

  @Test("a canvas-containing tree still retains phase products for partial reuse")
  func canvasTreeRetainsProducts() {
    let rootID = testIdentity("root")
    let text = PlacedNode(
      identity: testIdentity("root", "text"),
      bounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
      drawPayload: .text("hi")
    )
    let canvas = PlacedNode(
      identity: testIdentity("root", "canvas"),
      bounds: .init(origin: .init(x: 0, y: 1), size: .init(width: 4, height: 1)),
      drawPayload: .canvas(.init(drawing: Dots()))
    )
    let placed = PlacedNode(
      identity: rootID,
      bounds: .init(origin: .zero, size: .init(width: 4, height: 2)),
      children: [text, canvas]
    )
    let draw = DrawNode(identity: rootID, bounds: placed.bounds)

    let state = FrameTailRetainedState()
    // No overlay: the caller passes the same tree as baseline.
    state.storeCommittedFrame(
      artifacts(placed: placed, draw: draw),
      baselinePlacedTree: placed,
      proposal: .unspecified
    )

    let products = state.input(invalidatedIdentities: []).previousPhaseProducts
    // P1: the canvas no longer discards the whole frame's products; they are kept
    // so the per-subtree partial-reuse path can still reuse the text subtree.
    #expect(products != nil)
    // The whole-tree signature is nil because the tree has an unsupported node —
    // that only disables the wholeTreeIdentical fast path, not partial reuse.
    #expect(products?.signature == nil)
  }

  @Test("a fully supported tree retains products with a non-nil whole-tree signature")
  func supportedTreeRetainsSignedProducts() {
    let rootID = testIdentity("root")
    let placed = PlacedNode(
      identity: rootID,
      bounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
      drawPayload: .text("hi")
    )
    let draw = DrawNode(identity: rootID, bounds: placed.bounds)

    let state = FrameTailRetainedState()
    state.storeCommittedFrame(
      artifacts(placed: placed, draw: draw),
      baselinePlacedTree: placed,
      proposal: .unspecified
    )

    let products = state.input(invalidatedIdentities: []).previousPhaseProducts
    #expect(products != nil)
    #expect(products?.signature != nil)
  }

  @Test("an overlay-decorated frame retains no phase products")
  func overlayFrameRetainsNoProducts() {
    let rootID = testIdentity("root")
    let effective = PlacedNode(
      identity: rootID,
      bounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
      drawPayload: .text("effective")
    )
    let baseline = PlacedNode(
      identity: rootID,
      bounds: .init(origin: .zero, size: .init(width: 4, height: 1)),
      drawPayload: .text("baseline")
    )
    let draw = DrawNode(identity: rootID, bounds: effective.bounds)

    let state = FrameTailRetainedState()
    // effective != baseline stands in for an animation overlay decorating the
    // committed tree; such products must not be retained for baseline reuse.
    state.storeCommittedFrame(
      artifacts(placed: effective, draw: draw),
      baselinePlacedTree: baseline,
      proposal: .unspecified
    )

    #expect(state.input(invalidatedIdentities: []).previousPhaseProducts == nil)
  }
}
