import SwiftTUICore
import SwiftTUIViews

struct FrameTailInlineStageRenderer: Sendable {
  /// R3.2b gate: the raster-tier translation blit (`SWIFTTUI_SCROLL_BLIT`).
  /// Read once — the gates latch their first read by design.
  private static let scrollBlitEnabled = FeatureGate.scrollBlit.initialIsEnabled()

  /// Kill switch for the size-stability measure cutoff's certificate
  /// pre-pass (`SWIFTTUI_MEASURE_CUTOFF`, plan 2026-08-11-002 — default on
  /// since the Stage 4 promotion; `=0` restores the conservative spine
  /// re-measure wholesale).
  private static let measureCutoffEnabled =
    FeatureGate.measureSizeStabilityCutoff.initialIsEnabled()

  var layoutEngine: LayoutEngine
  var semanticExtractor: SemanticExtractor
  var drawExtractor: DrawExtractor
  var rasterizer: Rasterizer

  func renderInlineLayoutStage(
    _ input: FrameTailInput,
    clock: ContinuousClock?,
    beforeLayout: (@Sendable () -> Void)?
  ) -> FrameTailLayoutOutput {
    beforeLayout?()
    if Self.measureCutoffEnabled,
      let prePass = layoutEngine.preMeasureCutoffPrePass(
        resolved: input.resolved,
        passContext: input.layoutPassContext,
        animationExcludedIdentities: input.animationRedrawIdentities
          .union(input.animationSegmentTargetIdentities)
      )
    {
      var cutoffMetrics = prePass.metrics
      // Stage 3 (plan 2026-08-11-002): every certified root serves through
      // the derived session — the measure pass reads the patched copy while
      // place, damage, and diagnostics keep the original (D4). The
      // multi-sample certificate (retained + cached baselines including the
      // parent's ideal-round proposal, D1) is the general family's
      // soundness argument, and the layout shadow oracle is the authority:
      // a layout-shadow-divergence on a cutoff-served frame is a
      // stop-the-line event for this stage. A failed patch falls through
      // to the conservative pass with the pre-pass measures already in the
      // production cache.
      let servable = prePass.certificates
      if !servable.isEmpty,
        let patched = input.layoutPassContext.retainedLayout?
          .patchingCertifiedSubtrees(servable)
      {
        input.layoutPassContext.installPatchedMeasureSession(patched)
        cutoffMetrics.certificatesServed = servable.count
      }
      input.layoutPassContext.updateWorkMetrics {
        $0.preMeasureCutoff.merge(cutoffMetrics)
      }
      MeasureCutoffTrace.emit(cutoffMetrics)
    }
    // The pipeline's final measure entry is commit-grade by definition
    // (plan 2026-08-11-004 Stage 1): its product IS the frame's geometry.
    assert(
      layoutEngine.defaultMeasurementGrade == .commit,
      "the frame tail's measure entry must issue commit-grade requests"
    )
    let (measured, measureDuration) = measurePhase(clock: clock) {
      layoutEngine.measure(
        input.resolved,
        proposal: input.proposal,
        passContext: input.layoutPassContext
      )
    }
    let (placed, placeDuration) = measurePhase(clock: clock) {
      layoutEngine.place(
        input.resolved,
        measured: measured,
        passContext: input.layoutPassContext
      )
    }
    // The layout shadow oracle (`layout-shadow-divergence`): on a sampled
    // frame, re-run measure/place with every reuse tier disabled and compare
    // geometry. Runs outside the timed phases so `measureDuration` and
    // `placeDuration` stay production-only; the summary rides the layout
    // output back to the main-actor coordinator for recording. The production
    // trees above are returned untouched — the oracle never repairs.
    let layoutShadow: LayoutShadowComparisonSummary? =
      input.verifyLayoutShadow
      ? LayoutShadowOracle.comparisonSummary(
        resolved: input.resolved,
        proposal: input.proposal,
        productionMeasured: measured,
        productionPlaced: placed,
        scrollViewportContext: input.layoutPassContext.scrollViewportContext,
        customLayoutCompatibilityDepthLimit:
          input.layoutPassContext.customLayoutCompatibilityDepthLimit,
        measurementSeedSession: input.layoutPassContext.retainedLayout,
        productionLayoutRealizations: input.layoutPassContext.layoutDependentRealizations
      )
      : nil
    return FrameTailLayoutOutput(
      generation: input.generation,
      measured: measured,
      baselinePlaced: placed,
      measureDuration: measureDuration,
      placeDuration: placeDuration,
      layoutWork: input.layoutPassContext.workMetrics,
      workerCustomLayoutCacheUpdates: input.layoutPassContext.workerCustomLayoutCacheUpdates,
      workerEnqueueToStart: .zero,
      workerCompute: .zero,
      ranOffMain: false,
      layoutShadow: layoutShadow
    )
  }

  func renderInlineRasterTail(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    verifyIncrementalRasterDamage: Bool,
    clock: ContinuousClock?,
    beforeOverlayApply: (@Sendable () -> Void)?,
    beforeRaster: (@Sendable () -> Void)?
  ) -> FrameTailOutput {
    var placed = placed
    beforeOverlayApply?()
    applyPlacedAnimationOverlaySnapshot(
      animationOverlaySnapshot,
      to: &placed
    )
    // Past this point `placed` is the effective decorated tree for semantic,
    // draw, raster, and commit consumers. The retained layout baseline remains
    // `layout.baselinePlaced` and is the only placed tree stored for future
    // retained placement.
    let extractionProof = input.retained.phaseExtractionProof(
      for: input.proposal,
      placed: placed,
      animationOverlaySnapshot: animationOverlaySnapshot
    )
    let semantics = renderSemantics(
      placed: placed,
      retained: input.retained.previousPhaseProducts,
      proof: extractionProof,
      clock: clock
    )
    let draw = renderDraw(
      placed: placed,
      retained: input.retained.previousPhaseProducts,
      proof: extractionProof,
      clock: clock
    )
    // Damage resolution runs *after* draw extraction, not before: draw
    // extraction reuses retained subtrees, so the draw tree — not the placed
    // tree — is the last product the raster is a pure function of, and the only
    // sound diff basis.
    let rasterReusePlan = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: input.rootIdentity,
      placed: placed,
      draw: draw.draw,
      retainedLayout: input.retained.retainedLayout,
      previousDraw: input.retained.previousPhaseProducts?.draw,
      previousSurfaceTopology: input.retained.previousSurfaceTopology,
      animationRedrawIdentities: input.animationRedrawIdentities,
      animationOverlaySnapshot: animationOverlaySnapshot
    )
    // R3.2a: the tail-time committed-translation currency. Extracted from the
    // effective placed tree (the one the raster below is a function of) and
    // diffed against the previous committed frame's table — both ends of the
    // diff share provenance with the surfaces being compared, which is what
    // the present-time R2.2 candidate cannot guarantee (live registry offsets
    // can run ahead of pixels in async mode).
    let committedScrollRoutes = CommittedScrollRouteTable(placedRoot: placed)
    let committedScrollTranslation = CommittedScrollRouteTable.candidate(
      advancing: input.retained.previousScrollRouteTable,
      to: committedScrollRoutes
    )
    // R3.2b: the translation blit rides the incremental path only — the
    // resolver's barriers (animation, topology change, duplicate identities)
    // already produced `damage == nil` for every frame whose committed
    // products cannot back a translation claim.
    let translationPlan: RasterTranslationPlan? =
      if Self.scrollBlitEnabled,
        rasterReusePlan.damage != nil,
        let committedScrollTranslation,
        let previousSurface = input.retained.previousRasterSurface,
        let previousDraw = input.retained.previousPhaseProducts?.draw
      {
        FrameTailPresentationDamageResolver.translationPlan(
          candidate: committedScrollTranslation,
          surfaceSize: previousSurface.size,
          previousDraw: previousDraw,
          currentDraw: draw.draw
        )
      } else {
        nil
      }
    let raster = rasterizeDrawTree(
      input,
      draw: draw.draw,
      rasterReuseDamage: rasterReusePlan.damage,
      verifyIncrementalRasterDamage: verifyIncrementalRasterDamage,
      translation: translationPlan,
      clock: clock,
      beforeRaster: beforeRaster
    )
    let diagnostics = FrameTailDiagnostics(
      rasterPath: raster.path,
      rasterReuseBarriers: rasterReusePlan.barriers,
      measureDuration: layout.measureDuration,
      placeDuration: layout.placeDuration,
      semanticsDuration: semantics.duration,
      drawDuration: draw.duration,
      rasterDuration: raster.duration,
      layoutWork: layout.layoutWork,
      workerTimings: nil,
      measurementCache: layoutEngine.cache?.metrics,
      layoutShadow: layout.layoutShadow
    )
    return FrameTailOutput(
      generation: input.generation,
      measured: layout.measured,
      placed: placed,
      baselinePlaced: layout.baselinePlaced,
      overlayHasTransientDecoration: animationOverlaySnapshot.hasTransientDecoration,
      semantics: semantics.semantics,
      draw: draw.draw,
      raster: raster.surface,
      drawnIdentities: raster.drawnIdentities,
      presentationDamage: raster.presentationDamage,
      incrementalMismatch: raster.incrementalMismatch,
      committedScrollRoutes: committedScrollRoutes,
      committedScrollTranslation: committedScrollTranslation?.clamped(
        toSurface: raster.surface.size
      ),
      diagnostics: diagnostics,
      workerCompletedAt: nil
    )
  }

  private func renderSemantics(
    placed: PlacedNode,
    retained: RetainedFrameTailPhaseProducts?,
    proof: RetainedPhaseExtractionProof,
    clock: ContinuousClock?
  ) -> FrameTailSemanticsOutput {
    let retainedInput = retained.map {
      RetainedSemanticExtractionInput(
        previousSnapshot: $0.semantics,
        proof: proof
      )
    }
    let (semantics, duration) = measurePhase(clock: clock) {
      semanticExtractor.extract(from: placed, retained: retainedInput)
    }
    return .init(
      semantics: semantics,
      duration: duration
    )
  }

  private func renderDraw(
    placed: PlacedNode,
    retained: RetainedFrameTailPhaseProducts?,
    proof: RetainedPhaseExtractionProof,
    clock: ContinuousClock?
  ) -> FrameTailDrawOutput {
    let retainedInput = retained.map {
      RetainedDrawExtractionInput(
        previousDraw: $0.draw,
        previousDrawByNodeID: $0.drawByNodeID,
        proof: proof
      )
    }
    let (draw, duration) = measurePhase(clock: clock) {
      drawExtractor.extract(from: placed, retained: retainedInput)
    }
    return .init(
      draw: draw,
      duration: duration
    )
  }

  private func rasterizeDrawTree(
    _ input: FrameTailInput,
    draw: DrawNode,
    rasterReuseDamage: PresentationDamage?,
    verifyIncrementalRasterDamage: Bool,
    translation: RasterTranslationPlan? = nil,
    clock: ContinuousClock?,
    beforeRaster: (@Sendable () -> Void)?
  ) -> FrameTailRasterOutput {
    beforeRaster?()
    let previousSurface = input.retained.previousRasterSurface
    let (rasterized, duration) = measurePhase(clock: clock) {
      rasterizer.rasterizeCollectingVisibleIdentities(
        draw,
        minimumSize: minimumRasterSurfaceSize(for: input.proposal),
        previousSurface: previousSurface,
        damage: rasterReuseDamage,
        verifyIncrementalRasterDamage: verifyIncrementalRasterDamage,
        translation: translation
      )
    }
    let finalPresentationDamage =
      rasterized.presentationDamage
      ?? RasterSurfaceDamageDiff.diff(
        previous: previousSurface,
        current: rasterized.surface
      )
    return .init(
      path: rasterized.path,
      surface: rasterized.surface,
      drawnIdentities: rasterized.visibleIdentities,
      presentationDamage: finalPresentationDamage,
      incrementalMismatch: rasterized.incrementalMismatch,
      duration: duration
    )
  }

  private func measurePhase<Value>(
    clock: ContinuousClock?,
    _ operation: () -> Value
  ) -> (Value, Duration) {
    guard let clock else {
      return (operation(), .zero)
    }
    let start = clock.now
    let value = operation()
    return (value, start.duration(to: clock.now))
  }

  private func minimumRasterSurfaceSize(
    for proposal: ProposedSize
  ) -> CellSize {
    guard
      case .finite(let width) = proposal.width,
      case .finite(let height) = proposal.height
    else {
      return .zero
    }

    return .init(
      width: max(0, width),
      height: max(0, height)
    )
  }
}
