import Testing

@testable import SwiftTUICore

/// Locks the Stage-4 raster-reuse decoupling (G5): the surface topology
/// signature carries no runtime `Identity`, so a `ViewNodeID` re-key of a
/// portal/overlay root no longer perturbs the signature and forces a spurious
/// full-surface diff — while a genuine change to the structural `stableKey`
/// still registers.
@Suite("Surface topology signature stability")
struct SurfaceTopologySignatureTests {
  private let unitBounds = CellRect(origin: .zero, size: .init(width: 10, height: 10))

  private func overlayTree(overlayIdentitySuffix: String, stableKey: String) -> PlacedNode {
    PlacedNode(
      identity: testIdentity("Root"),
      bounds: unitBounds,
      children: [
        PlacedNode(
          identity: testIdentity("Root", overlayIdentitySuffix),
          bounds: unitBounds,
          surfaceComposition: SurfaceCompositionMetadata(
            role: .stackingContext,
            stableKey: stableKey
          )
        )
      ]
    )
  }

  @Test("signature is stable when only a participating node's runtime identity changes")
  func signatureStableUnderRuntimeRekey() {
    let key = "overlay-stack:Root/OverlayStack"
    let before = SurfaceTopologySignature(
      placedRoot: overlayTree(overlayIdentitySuffix: "ID[before]", stableKey: key))
    let after = SurfaceTopologySignature(
      placedRoot: overlayTree(overlayIdentitySuffix: "ID[after]", stableKey: key))

    #expect(!after.differs(from: before))
  }

  @Test("signature still registers a participating node's structural stableKey change")
  func signatureChangesUnderStableKeyChange() {
    // Identical runtime identity; only the structural stable key moves.
    let original = SurfaceTopologySignature(
      placedRoot: overlayTree(
        overlayIdentitySuffix: "ID[x]", stableKey: "overlay-stack:Root/StackA"))
    let moved = SurfaceTopologySignature(
      placedRoot: overlayTree(
        overlayIdentitySuffix: "ID[x]", stableKey: "overlay-stack:Root/StackB"))

    #expect(moved.differs(from: original))
  }
}
