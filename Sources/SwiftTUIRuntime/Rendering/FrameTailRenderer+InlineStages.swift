import SwiftTUICore
import SwiftTUIViews

struct FrameTailInlineStageRenderer: Sendable {
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
      ranOffMain: false
    )
  }

  func renderInlineRasterTail(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?,
    beforeRaster: (@Sendable () -> Void)?
  ) -> FrameTailOutput {
    var placed = placed
    applyPlacedAnimationOverlaySnapshot(
      animationOverlaySnapshot,
      to: &placed
    )
    // Past this point `placed` is the effective decorated tree for semantic,
    // draw, raster, and commit consumers. The retained layout baseline remains
    // `layout.baselinePlaced` and is the only placed tree stored for future
    // retained placement.
    let presentationDamage = FrameTailPresentationDamageResolver.resolve(
      rootIdentity: input.rootIdentity,
      placed: placed,
      retainedLayout: input.retained.retainedLayout
    )
    let semantics = renderSemantics(
      placed: placed,
      clock: clock
    )
    let draw = renderDraw(
      placed: placed,
      clock: clock
    )
    let raster = rasterizeDrawTree(
      input,
      draw: draw.draw,
      presentationDamage: presentationDamage,
      clock: clock,
      beforeRaster: beforeRaster
    )
    let diagnostics = FrameTailDiagnostics(
      measureDuration: layout.measureDuration,
      placeDuration: layout.placeDuration,
      semanticsDuration: semantics.duration,
      drawDuration: draw.duration,
      rasterDuration: raster.duration,
      layoutWork: layout.layoutWork,
      workerTimings: nil,
      measurementCache: layoutEngine.cache?.metrics
    )
    return FrameTailOutput(
      generation: input.generation,
      measured: layout.measured,
      placed: placed,
      baselinePlaced: layout.baselinePlaced,
      semantics: semantics.semantics,
      draw: draw.draw,
      raster: raster.surface,
      drawnIdentities: raster.drawnIdentities,
      presentationDamage: raster.presentationDamage,
      diagnostics: diagnostics,
      workerCompletedAt: nil
    )
  }

  private func renderSemantics(
    placed: PlacedNode,
    clock: ContinuousClock?
  ) -> FrameTailSemanticsOutput {
    let (semantics, duration) = measurePhase(clock: clock) {
      semanticExtractor.extract(from: placed)
    }
    return .init(
      semantics: semantics,
      duration: duration
    )
  }

  private func renderDraw(
    placed: PlacedNode,
    clock: ContinuousClock?
  ) -> FrameTailDrawOutput {
    let (draw, duration) = measurePhase(clock: clock) {
      drawExtractor.extract(from: placed)
    }
    return .init(
      draw: draw,
      duration: duration
    )
  }

  private func rasterizeDrawTree(
    _ input: FrameTailInput,
    draw: DrawNode,
    presentationDamage: PresentationDamage?,
    clock: ContinuousClock?,
    beforeRaster: (@Sendable () -> Void)?
  ) -> FrameTailRasterOutput {
    beforeRaster?()
    let (rasterized, duration) = measurePhase(clock: clock) {
      rasterizer.rasterizeCollectingVisibleIdentities(
        draw,
        minimumSize: minimumRasterSurfaceSize(for: input.proposal),
        previousSurface: input.retained.previousRasterSurface,
        damage: presentationDamage
      )
    }
    return .init(
      surface: rasterized.surface,
      drawnIdentities: rasterized.visibleIdentities,
      presentationDamage: rasterized.presentationDamage,
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
