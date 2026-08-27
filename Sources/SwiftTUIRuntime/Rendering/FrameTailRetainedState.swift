import SwiftTUICore
import Synchronization

/// Holds the previous committed frame's products so the next frame's tail can
/// reuse them.
///
/// This is the frame tail's only piece of cross-frame mutable state, so it is
/// kept apart from the value-type model structs in `FrameTailModels.swift`. It
/// retains three things behind a `Mutex`:
///
///  - a `RetainedFrameIndex` over the baseline (pre-overlay) layout products,
///    for retained measurement and placement,
///  - the previous committed raster surface and visual surface topology, used
///    to derive actual damage and decide whether raster reuse hints are safe, and
///  - the previous committed frame's drawn-identity set, used as a geometric
///    visibility signal for scheduling policy (e.g. offscreen-frame elision),
///    and
///  - previous committed semantic/draw phase products for reuse only when the
///    next frame proves the effective placed tree is identical.
///
/// It never stores or previews an in-flight candidate frame.
final class FrameTailRetainedState: Sendable {
  private struct State: Sendable {
    var previousFrameIndex: RetainedFrameIndex?
    var previousDrawnIdentities: Set<Identity>?
    var previousRasterSurface: RasterSurface?
    var previousSurfaceTopology: SurfaceTopologySignature?
    var previousPhaseProducts: RetainedFrameTailPhaseProducts?
    var previousScrollRouteTable: CommittedScrollRouteTable?
  }

  private let state = Mutex(State())

  /// The set of identities that were geometrically visible in the previous
  /// committed frame. Returns an empty set when no frame has committed yet.
  var previousDrawnIdentities: Set<Identity> {
    state.withLock { $0.previousDrawnIdentities ?? [] }
  }

  /// Occupancy reading for the profiling memory signal. Reads the retained
  /// frame index under the same lock that guards the stored state.
  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    state.withLock { state in
      MemoryMetricSnapshot(
        name: "RetainedFrameIndex.placedByNodeID",
        count: state.previousFrameIndex?.placedByNodeID.count ?? 0,
        approxBytes: state.previousRasterSurface.map { $0.size.width * $0.size.height },
        detail: [
          "resolved": state.previousFrameIndex?.resolvedByNodeID.count ?? 0,
          "measured": state.previousFrameIndex?.measuredByNodeID.count ?? 0,
          "structural": state.previousFrameIndex?.structuralFrame.postorder.count ?? 0,
          "placedFrameEntries": state.previousFrameIndex?.placedFrameEntryCount ?? 0,
          "phaseProducts": state.previousPhaseProducts == nil ? 0 : 1,
        ]
      )
    }
  }

  func input(
    invalidatedIdentities: Set<Identity>
  ) -> FrameTailRetainedInput {
    // Retained input is previous committed-frame state only: baseline layout
    // products for retained measurement/placement, plus the previous committed
    // raster surface/topology for damage work. It never previews a candidate.
    state.withLock { state in
      .init(
        retainedLayout: RetainedLayoutSession(
          previousFrameIndex: state.previousFrameIndex,
          invalidatedIdentities: invalidatedIdentities
        ),
        previousRasterSurface: state.previousRasterSurface,
        previousSurfaceTopology: state.previousSurfaceTopology,
        previousPhaseProducts: state.previousPhaseProducts,
        previousScrollRouteTable: state.previousScrollRouteTable
      )
    }
  }

  /// Stores the frame's artifacts so the next frame's pipeline can
  /// reuse cached layout.
  ///
  /// `baselinePlacedTree` is the **pre-overlay** placed tree — the
  /// canonical layout result from `LayoutEngine.place`, before the
  /// animation controller injected any transient removal overlays.
  /// The retained-layout cache indexes this baseline so future tick
  /// frames reuse stable bounds/identities rather than the
  /// animation-decorated tree; overlays are re-injected from the
  /// controller's own removal-entry state on each tick.
  ///
  /// When no overlays were injected this frame, pass the same
  /// `placedTree` as baseline — the two are identical.
  ///
  /// `overlayHasTransientDecoration` is the tail's own flag; direct callers
  /// (tests) may omit it, in which case the effective tree differing from the
  /// baseline stands in for a transient decoration, the pre-adoption proxy.
  func storeCommittedFrame(
    _ artifacts: FrameArtifacts,
    baselinePlacedTree: PlacedNode,
    overlayHasTransientDecoration: Bool? = nil,
    proposal: ProposedSize,
    verifyIndexPatch: Bool = true
  ) {
    var indexable = artifacts
    indexable.placedTree = baselinePlacedTree
    // Phase products are reusable next frame only when no animation *sample*
    // decorated this frame's committed (effective) tree: an exit overlay or a
    // live insertion/matched offset is a one-frame decoration the next frame
    // does not repeat. Co-present matched-geometry adoption is the exception
    // — it decorates every frame with the same layout identically — so the
    // gate keys on the tail's transient flag rather than on the effective
    // tree byte-matching the pre-overlay baseline (the previous proxy, which
    // adoption would fail every frame). The stored signature is OPTIONAL: a
    // tree with an unsupported node (`.canvas`/custom layout) yields `nil`,
    // which previously discarded the products entirely — disabling reuse
    // tree-wide. Keeping the products with a `nil` signature disables only the
    // whole-tree fast path; the per-subtree partial-reuse path still reuses
    // every supported subtree.
    let hasTransientDecoration =
      overlayHasTransientDecoration ?? (artifacts.placedTree != baselinePlacedTree)
    let effectiveMatchesBaseline = !hasTransientDecoration
    state.withLock { state in
      state.previousFrameIndex = .init(
        patching: state.previousFrameIndex,
        with: indexable,
        verifyingAgainstFullRebuild: verifyIndexPatch
      )
      state.previousDrawnIdentities = artifacts.drawnIdentities
      state.previousRasterSurface = artifacts.rasterSurface
      state.previousSurfaceTopology = SurfaceTopologySignature(
        placedRoot: artifacts.placedTree
      )
      // Advances with the raster surface above: the next tail's translation
      // baseline must describe exactly the committed frame whose surface it
      // will translate (R3.2a provenance rule).
      state.previousScrollRouteTable = artifacts.committedScrollRoutes
      state.previousPhaseProducts =
        if effectiveMatchesBaseline {
          RetainedFrameTailPhaseProducts(
            proposal: proposal,
            signature: RetainedPhaseExtractionSignature.make(from: artifacts.placedTree),
            semantics: artifacts.semanticSnapshot.retainedExtractionProduct,
            draw: artifacts.drawTree,
            drawByNodeID: Self.drawIndex(artifacts.drawTree)
          )
        } else {
          nil
        }
    }
  }

  /// Index the previous draw tree by `ViewNodeID` for retained-draw reuse.
  ///
  /// A `ViewNodeID` is **not** unique across the draw tree. Two siblings under
  /// one `.id(_:)` claim the same entity home and report one `ViewNodeID` (see
  /// `ViewNode.claimExactIdentityOccurrence`), so a plain
  /// `storage[viewNodeID] = node` kept only the last writer and served it to
  /// *both* siblings on the next frame — one sibling's content rendered twice
  /// and the other's dropped. Duplicate ids are undefined user input, but
  /// silently painting the wrong content is not an acceptable response to
  /// them.
  ///
  /// Colliding keys are therefore **withheld** rather than disambiguated. The
  /// extractor falls through to a fresh extraction for those nodes, which is
  /// always correct — fresh extraction is the oracle retained reuse is
  /// measured against. Disambiguating by occurrence is not available here:
  /// `DrawNode` carries no occurrence, and this index is built after resolve.
  /// The cost is lost reuse on duplicated ids only.
  private static func drawIndex(_ root: DrawNode) -> [ViewNodeID: DrawNode] {
    var storage: [ViewNodeID: DrawNode] = [:]
    var collided: Set<ViewNodeID> = []
    indexDrawNode(root, into: &storage, collided: &collided)
    for viewNodeID in collided {
      storage.removeValue(forKey: viewNodeID)
    }
    return storage
  }

  private static func indexDrawNode(
    _ node: DrawNode,
    into storage: inout [ViewNodeID: DrawNode],
    collided: inout Set<ViewNodeID>
  ) {
    if let viewNodeID = node.viewNodeID {
      if storage.updateValue(node, forKey: viewNodeID) != nil {
        collided.insert(viewNodeID)
      }
    }
    for child in node.children {
      indexDrawNode(child, into: &storage, collided: &collided)
    }
  }
}
