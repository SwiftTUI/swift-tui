import SwiftTUICore
import Synchronization

/// Holds the previous committed frame's products so the next frame's tail can
/// reuse them.
///
/// This is the frame tail's only piece of cross-frame mutable state, so it is
/// kept apart from the value-type model structs in `FrameTailModels.swift`. It
/// retains exactly two things behind a `Mutex`:
///
///  - a `RetainedFrameIndex` over the baseline (pre-overlay) layout products,
///    for retained measurement and placement, and
///  - the previous committed raster surface and visual surface topology, used
///    to derive actual damage and decide whether raster reuse hints are safe.
///
/// It never stores or previews an in-flight candidate frame.
final class FrameTailRetainedState: Sendable {
  private struct State: Sendable {
    var previousFrameIndex: RetainedFrameIndex?
    var previousRasterSurface: RasterSurface?
    var previousSurfaceTopology: SurfaceTopologySignature?
  }

  private let state = Mutex(State())

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
        previousSurfaceTopology: state.previousSurfaceTopology
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
    baselinePlacedTree: PlacedNode
  ) {
    var indexable = artifacts
    indexable.placedTree = baselinePlacedTree
    state.withLock { state in
      state.previousFrameIndex = .init(frame: indexable)
      state.previousRasterSurface = artifacts.rasterSurface
      state.previousSurfaceTopology = SurfaceTopologySignature(
        placedRoot: artifacts.placedTree
      )
    }
  }
}
