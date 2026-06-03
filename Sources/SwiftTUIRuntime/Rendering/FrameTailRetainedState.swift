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
        name: "RetainedFrameIndex.placedByIdentity",
        count: state.previousFrameIndex?.placedByIdentity.count ?? 0,
        approxBytes: state.previousRasterSurface.map { $0.size.width * $0.size.height },
        detail: [
          "resolved": state.previousFrameIndex?.resolvedByIdentity.count ?? 0,
          "measured": state.previousFrameIndex?.measuredByIdentity.count ?? 0,
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
        previousPhaseProducts: state.previousPhaseProducts
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
  func storeCommittedFrame(
    _ artifacts: FrameArtifacts,
    baselinePlacedTree: PlacedNode,
    proposal: ProposedSize
  ) {
    var indexable = artifacts
    indexable.placedTree = baselinePlacedTree
    let effectiveSignature = RetainedPhaseExtractionSignature.make(
      from: artifacts.placedTree
    )
    let baselineSignature = RetainedPhaseExtractionSignature.make(
      from: baselinePlacedTree
    )
    state.withLock { state in
      state.previousFrameIndex = .init(
        patching: state.previousFrameIndex,
        with: indexable
      )
      state.previousDrawnIdentities = artifacts.drawnIdentities
      state.previousRasterSurface = artifacts.rasterSurface
      state.previousSurfaceTopology = SurfaceTopologySignature(
        placedRoot: artifacts.placedTree
      )
      state.previousPhaseProducts =
        if let effectiveSignature,
          effectiveSignature == baselineSignature
        {
          RetainedFrameTailPhaseProducts(
            proposal: proposal,
            signature: effectiveSignature,
            semantics: artifacts.semanticSnapshot.retainedExtractionProduct,
            draw: artifacts.drawTree,
            drawByIdentity: Self.drawIndex(artifacts.drawTree)
          )
        } else {
          nil
        }
    }
  }

  private static func drawIndex(_ root: DrawNode) -> [Identity: DrawNode] {
    var storage: [Identity: DrawNode] = [:]
    indexDrawNode(root, into: &storage)
    return storage
  }

  private static func indexDrawNode(
    _ node: DrawNode,
    into storage: inout [Identity: DrawNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      indexDrawNode(child, into: &storage)
    }
  }
}
