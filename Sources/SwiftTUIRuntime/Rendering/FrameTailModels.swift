import SwiftTUICore
import Synchronization

// `FrameTailRetainedState` — the frame tail's cross-frame mutable state — lives
// in `FrameTailRetainedState.swift`. This file holds the value-type models.

struct FrameTailRetainedInput {
  /// Previous committed baseline layout products for retained measure/place.
  var retainedLayout: RetainedLayoutSession
  /// Previous committed raster surface used for actual raster damage.
  var previousRasterSurface: RasterSurface?
  /// Previous committed effective visual surface topology.
  var previousSurfaceTopology: SurfaceTopologySignature?
  /// Previous committed effective phase products that are safe to reuse only
  /// when the current frame can prove the effective placed tree is identical.
  var previousPhaseProducts: RetainedFrameTailPhaseProducts?

  package func phaseExtractionProof(
    for proposal: ProposedSize,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot
  ) -> RetainedPhaseExtractionProof {
    guard
      let previous = previousPhaseProducts,
      previous.proposal == proposal,
      animationOverlaySnapshot.isEmpty
    else {
      return .none
    }
    if let currentSignature = RetainedPhaseExtractionSignature.make(from: placed),
      previous.signature == currentSignature
    {
      return .wholeTreeIdentical
    }
    guard let previousFrameIndex = retainedLayout.previousFrameIndex else {
      return .none
    }

    var reusableRoots: Set<Identity> = []
    collectReusablePhaseSubtrees(
      placed,
      previousFrameIndex: previousFrameIndex,
      invalidationSummary: retainedLayout.invalidationSummary,
      reusableRoots: &reusableRoots
    )
    return reusableRoots.isEmpty ? .none : .subtreesIdentical(reusableRoots)
  }

  private func collectReusablePhaseSubtrees(
    _ node: PlacedNode,
    previousFrameIndex: RetainedFrameIndex,
    invalidationSummary: RetainedInvalidationSummary,
    reusableRoots: inout Set<Identity>
  ) {
    if !invalidationSummary.intersectsSubtree(at: node.identity),
      let previousPlaced = previousFrameIndex.placedNode(for: node.identity),
      let currentSignature = RetainedPhaseExtractionSignature.make(from: node),
      let previousSignature = RetainedPhaseExtractionSignature.make(from: previousPlaced),
      currentSignature == previousSignature
    {
      reusableRoots.insert(node.identity)
      return
    }

    for child in node.children {
      collectReusablePhaseSubtrees(
        child,
        previousFrameIndex: previousFrameIndex,
        invalidationSummary: invalidationSummary,
        reusableRoots: &reusableRoots
      )
    }
  }
}

struct RetainedFrameTailPhaseProducts: Sendable {
  var proposal: ProposedSize
  var signature: RetainedPhaseExtractionSignature
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var drawByIdentity: [Identity: DrawNode]
}

/// Worker-safe input for measure/place through raster work.
///
/// The resolved tree is the current frame's canonical resolved product. Retained
/// data is previous committed baseline state; it is not a preview of any
/// in-flight candidate.
struct FrameTailInput {
  var generation: RenderGeneration
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var rootIdentity: Identity
  var retained: FrameTailRetainedInput
  var layoutPassContext: LayoutPassContext
}

struct FrameTailDiagnostics {
  var measureDuration: Duration
  var placeDuration: Duration
  var semanticsDuration: Duration
  var drawDuration: Duration
  var rasterDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerTimings: FrameWorkerTimings?
  var measurementCache: MeasurementCacheMetrics?
}

struct FrameTailLayoutOutput {
  var generation: RenderGeneration
  var measured: MeasuredNode
  /// Canonical pre-overlay placed tree produced by layout. This is the retained
  /// layout baseline and animation-capture input; it must not contain transient
  /// removal overlays.
  var baselinePlaced: PlacedNode
  var measureDuration: Duration
  var placeDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  var workerEnqueueToStart: Duration
  var workerCompute: Duration
  var ranOffMain: Bool
}

struct ReconciledFrameTailLayout {
  var input: FrameTailInput
  var layout: FrameTailLayoutOutput
  var resolved: ResolvedNode
  var runtimeIssues: [RuntimeIssue]
}

struct FrameTailSemanticsOutput {
  var semantics: SemanticSnapshot
  var duration: Duration
}

struct FrameTailDrawOutput {
  var draw: DrawNode
  var duration: Duration
}

struct FrameTailRasterOutput {
  var surface: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var duration: Duration
}

struct FrameTailOutput {
  var generation: RenderGeneration
  var measured: MeasuredNode
  /// Effective current-frame placed tree consumed by semantics, draw, raster,
  /// and commit. This may include transient animation overlays.
  var placed: PlacedNode
  /// Canonical pre-overlay layout product retained for future layout reuse.
  var baselinePlaced: PlacedNode
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var raster: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var diagnostics: FrameTailDiagnostics
  var workerCompletedAt: ContinuousClock.Instant?
}

struct AsyncFrameTailDraftOutput {
  /// Tail input that was actually consumed by the worker path.
  var frameTailInput: FrameTailInput
  /// Canonical baseline layout output before overlay decoration.
  var layout: FrameTailLayoutOutput
  /// Effective tail output after overlay decoration, semantics, draw, and raster.
  var tail: FrameTailOutput
  /// Resolved tree after late layout-dependent content reconciliation.
  var resolved: ResolvedNode
  var runtimeIssues: [RuntimeIssue]
  var renderSuspensionDuration: Duration
}

struct FrameTailWorkerResult<Value> {
  var value: Value
  var enqueueToStart: Duration
  var compute: Duration
  var completedAt: ContinuousClock.Instant?
}

final class RenderGenerationSequencer: Sendable {
  private let nextRawValue = Mutex<UInt64>(1)

  func next() -> RenderGeneration {
    nextRawValue.withLock { value in
      let generation = RenderGeneration(value)
      value &+= 1
      return generation
    }
  }
}

package struct FrameTailRenderHooks: Sendable {
  package var beforeLayout: (@Sendable () -> Void)?
  /// Fires on the frame-tail worker immediately before the animation overlay is
  /// applied to the placed tree (`applyPlacedAnimationOverlaySnapshot`), i.e.
  /// just before the off-main `Boxed._modify` writes that decorate the shared
  /// tree. Production default `nil` (no-op). A test can park the worker here to
  /// hold the box-mutation window open while the main actor concurrently reads
  /// the aliased tree — see the run-loop memory-corruption repro (swift-tui#12).
  /// The existing `beforeRaster` seam fires *after* the overlay write, so it
  /// cannot bracket that mutation.
  package var beforeOverlayApply: (@Sendable () -> Void)?
  package var beforeRaster: (@Sendable () -> Void)?

  package init(
    beforeLayout: (@Sendable () -> Void)? = nil,
    beforeOverlayApply: (@Sendable () -> Void)? = nil,
    beforeRaster: (@Sendable () -> Void)? = nil
  ) {
    self.beforeLayout = beforeLayout
    self.beforeOverlayApply = beforeOverlayApply
    self.beforeRaster = beforeRaster
  }
}

package struct FrameRenderSuspensionHooks: Sendable {
  package var onBegin: (@Sendable () -> Void)?
  package var onEnd: (@Sendable () -> Void)?

  package init(
    onBegin: (@Sendable () -> Void)? = nil,
    onEnd: (@Sendable () -> Void)? = nil
  ) {
    self.onBegin = onBegin
    self.onEnd = onEnd
  }
}
