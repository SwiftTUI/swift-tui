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
  /// Previous committed frame's scroll-route table — the baseline the
  /// tail-time committed-translation candidate diffs against (R3.2a).
  /// Advances with ``previousRasterSurface`` so the claim and the surface it
  /// is about always come from the same committed frame.
  var previousScrollRouteTable: CommittedScrollRouteTable? = nil

  package func phaseExtractionProof(
    for proposal: ProposedSize,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot
  ) -> RetainedPhaseExtractionProof {
    // Adoption-only decoration keeps the products reusable: the previous
    // products were extracted from an equally adopted effective tree, the
    // whole-tree signature below compares effective against effective, and
    // an adopted subtree differs from its baseline index entry so the
    // per-subtree path re-extracts it (conservative, sound).
    guard
      let previous = previousPhaseProducts,
      previous.proposal == proposal,
      !animationOverlaySnapshot.hasTransientDecoration
    else {
      return .none
    }
    if let previousSignature = previous.signature,
      let currentSignature = RetainedPhaseExtractionSignature.make(from: placed),
      previousSignature == currentSignature
    {
      return .wholeTreeIdentical
    }
    guard let previousFrameIndex = retainedLayout.previousFrameIndex else {
      return .none
    }

    var reusableRoots: Set<Identity> = []
    collectReusablePhaseSubtrees(
      placed,
      inheritedOpacity: 1,
      previousFrameIndex: previousFrameIndex,
      invalidationSummary: retainedLayout.invalidationSummary,
      reusableRoots: &reusableRoots
    )
    return reusableRoots.isEmpty ? .none : .subtreesIdentical(reusableRoots)
  }

  private func collectReusablePhaseSubtrees(
    _ node: PlacedNode,
    inheritedOpacity: Double,
    previousFrameIndex: RetainedFrameIndex,
    invalidationSummary: RetainedInvalidationSummary,
    reusableRoots: inout Set<Identity>
  ) {
    // Draw extraction bakes the accumulated ancestor opacity into emitted
    // commands, so a subtree whose own signature is unchanged still re-emits
    // differently when an ANCESTOR fade changed. The signature covers the
    // subtree's interior; the inherited factor at its root covers everything
    // outside it — both must match the previous frame before reuse is sound.
    if !invalidationSummary.intersectsSubtree(at: node.identity),
      let previousPlaced = previousFrameIndex.placedNode(for: node.identity),
      previousInheritedOpacity(for: node.identity, in: previousFrameIndex) == inheritedOpacity,
      let currentSignature = RetainedPhaseExtractionSignature.make(from: node),
      let previousSignature = RetainedPhaseExtractionSignature.make(from: previousPlaced),
      currentSignature == previousSignature
    {
      reusableRoots.insert(node.identity)
      return
    }

    let childInheritedOpacity =
      inheritedOpacity * (node.drawMetadata.explicitOpacity ?? 1)
    for child in node.children {
      collectReusablePhaseSubtrees(
        child,
        inheritedOpacity: childInheritedOpacity,
        previousFrameIndex: previousFrameIndex,
        invalidationSummary: invalidationSummary,
        reusableRoots: &reusableRoots
      )
    }
  }

  /// The product of `.opacity` factors STRICTLY ABOVE `identity` in the
  /// previous committed placed tree, or `nil` when the ancestor chain cannot
  /// be established unambiguously — the caller then denies reuse, which is
  /// always safe.
  private func previousInheritedOpacity(
    for identity: Identity,
    in previousFrameIndex: RetainedFrameIndex
  ) -> Double? {
    guard let path = previousFrameIndex.placedPath(to: identity) else {
      return nil
    }
    return path.dropLast().reduce(1) { partial, ancestor in
      partial * (ancestor.drawMetadata.explicitOpacity ?? 1)
    }
  }
}

struct RetainedFrameTailPhaseProducts: Sendable {
  var proposal: ProposedSize
  /// The whole-tree extraction signature, or `nil` when the committed tree
  /// contained a node that does not support retained phase extraction
  /// (`.canvas`/`.foreignSurface`/custom layout). A `nil` signature disables
  /// only the `.wholeTreeIdentical` fast path; the per-subtree partial-reuse
  /// path (`collectReusablePhaseSubtrees`) still reuses the supported subtrees
  /// instead of the whole tree being re-extracted from scratch.
  var signature: RetainedPhaseExtractionSignature?
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var drawByNodeID: [ViewNodeID: DrawNode]
}

/// Worker-safe input for measure/place through raster work.
///
/// The resolved tree is the current frame's canonical resolved product. Retained
/// data is previous committed baseline state; it is not a preview of any
/// in-flight candidate.
struct FrameTailInput {
  var generation: RenderGeneration
  /// Canonical pre-animation resolved product. Tail stages that write back to
  /// ViewGraph must consume this value, never transient presentation overrides.
  var canonicalResolved: ResolvedNode
  /// Presentation tree for measure/place/draw.
  var resolved: ResolvedNode
  var proposal: ProposedSize
  var rootIdentity: Identity
  var retained: FrameTailRetainedInput
  var layoutPassContext: LayoutPassContext
  /// O(1) ViewGraph animation-input currency captured with the canonical tree.
  var graphAnimationInputToken: UInt64
  /// Declarations freshly evaluated while producing the canonical tree. This
  /// complements the resolve work tracker in the animation skip proof.
  var evaluatedNodeIDs: Set<ViewNodeID>
  /// Identities whose rendered cells the head's animation-injection stage
  /// rewrote *after* resolve, from ``AnimationTickResult/redrawIdentities``.
  ///
  /// These changes are invisible to `invalidatedIdentities`: interpolation
  /// mutates the already-resolved tree, so an animating node's drawn output can
  /// change with its identity absent from `directlyInvalidated`. The damage
  /// resolver does not consume these as damage — damage is a draw-tree diff —
  /// but a non-empty set marks the frame as animation-rewritten, and the
  /// resolver barriers it rather than extend its soundness argument across the
  /// animation stages (see the barrier comment in
  /// `FrameTailPresentationDamageResolver.resolve`).
  var animationRedrawIdentities: Set<Identity> = []
  /// Identity union of the frame's active animation segments, latched at
  /// input construction. The measure-cutoff pre-pass excludes dirty roots
  /// targeted by an active segment (plan 2026-08-11-002 D9) — animated nodes
  /// usually change size per tick, so certification would be pure overhead.
  var animationSegmentTargetIdentities: Set<Identity> = []
  /// Latched from `SoundnessProbeConfiguration.isSampledFrame` on the main
  /// actor when the input is built (the layout stage may run off-main, where
  /// that `@MainActor` state is unreadable). On a sampled frame the layout
  /// stage re-runs measure/place with all reuse disabled and compares — the
  /// `layout-shadow-divergence` oracle.
  var verifyLayoutShadow: Bool = false
}

struct FrameTailDiagnostics {
  /// Which rasterizer path produced this frame's surface, and why damage
  /// production barriered when it did.
  ///
  /// Institutionalized rather than reconstructed: the incremental tier was
  /// dormant for the whole of its existence and nothing in the codebase could
  /// say so — the TermUIPerf lanes checked in to prove it measured a flat zero,
  /// and establishing that required hand-patching the rasterizer. Tests and the
  /// perf harness now assert on this instead.
  var rasterPath: Rasterizer.RasterPath
  var rasterReuseBarriers: Set<FrameTailRasterReuseBarrier>
  var measureDuration: Duration
  var placeDuration: Duration
  var semanticsDuration: Duration
  var drawDuration: Duration
  var rasterDuration: Duration
  var layoutWork: LayoutWorkMetrics
  var workerTimings: FrameWorkerTimings?
  var measurementCache: MeasurementCacheMetrics?
  /// The layout shadow oracle's verdict for this frame, when the sampled
  /// comparison ran (`layout-shadow-divergence`).
  var layoutShadow: LayoutShadowComparisonSummary?
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
  /// Non-nil when the sampled layout shadow comparison ran for this pass.
  /// Late-preference reconciliation merges the summaries of every pass it
  /// runs; the main-actor frame coordinator records the merged verdict on the
  /// soundness probe — the tail itself may run off-main.
  var layoutShadow: LayoutShadowComparisonSummary?
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
  var path: Rasterizer.RasterPath
  var surface: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  var incrementalMismatch: Rasterizer.IncrementalRasterMismatch?
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
  /// Whether an animation sample (exit overlay, insertion or matched offset)
  /// decorated `placed` this frame. The commit-side products gate keys on
  /// this rather than on `placed == baselinePlaced`: co-present adoption
  /// decorates every frame with the same layout identically, so its phase
  /// products stay reusable.
  var overlayHasTransientDecoration: Bool
  var semantics: SemanticSnapshot
  var draw: DrawNode
  var raster: RasterSurface
  var drawnIdentities: Set<Identity>
  var presentationDamage: PresentationDamage?
  /// Non-nil when the incremental-repaint verification oracle caught (and
  /// repaired) an incomplete-damage mismatch this frame. The main-actor frame
  /// coordinator records it on the soundness probe — the tail itself may run
  /// off-main.
  var incrementalMismatch: Rasterizer.IncrementalRasterMismatch?
  /// This frame's committed scroll-route table, extracted from the effective
  /// placed tree (R3.2a). Stored with the committed frame as the next tail's
  /// translation baseline.
  var committedScrollRoutes: CommittedScrollRouteTable?
  /// The tail-time committed-products translation candidate, clamped to the
  /// rasterized surface (R3.2a). Diagnostics-only in this slice.
  var committedScrollTranslation: CommittedScrollTranslation?
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
  /// Resolved tree after late layout-realized content reconciliation.
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
