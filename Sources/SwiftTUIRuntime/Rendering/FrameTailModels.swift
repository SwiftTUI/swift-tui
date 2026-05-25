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
  package var beforeRaster: (@Sendable () -> Void)?

  package init(
    beforeLayout: (@Sendable () -> Void)? = nil,
    beforeRaster: (@Sendable () -> Void)? = nil
  ) {
    self.beforeLayout = beforeLayout
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
