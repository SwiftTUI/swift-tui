import SwiftTUICore
import SwiftTUIViews
import Synchronization

final class FrameTailRenderer: Sendable {
  private let layoutEngine: LayoutEngine
  private let semanticExtractor: SemanticExtractor
  private let drawExtractor: DrawExtractor
  private let rasterizer: Rasterizer
  private let retainedState = FrameTailRetainedState()
  private let renderHooks = Mutex<FrameTailRenderHooks?>(nil)
  private let suspensionHooks = Mutex<FrameRenderSuspensionHooks?>(nil)
  private let workerExecutor = FrameTailWorkerExecutor()

  init(
    layoutEngine: LayoutEngine,
    semanticExtractor: SemanticExtractor,
    drawExtractor: DrawExtractor,
    rasterizer: Rasterizer
  ) {
    self.layoutEngine = layoutEngine
    self.semanticExtractor = semanticExtractor
    self.drawExtractor = drawExtractor
    self.rasterizer = rasterizer
  }

  package var memoryMetricSnapshot: MemoryMetricSnapshot {
    retainedState.memoryMetricSnapshot
  }

  /// The set of identities drawn in the last committed frame; empty before the first commit.
  ///
  /// Reads the `Mutex`-guarded retained state directly rather than via
  /// `workerExecutor.sync` (unlike the sibling accessors): the off-screen
  /// elision gate calls this on the main actor right after animation injection,
  /// and only ever observes the *previous committed* frame's value (never an
  /// in-flight candidate), so routing it through the worker executor would only
  /// serialize the hot gate against worker jobs for no correctness gain.
  var previousDrawnIdentities: Set<Identity> {
    retainedState.previousDrawnIdentities
  }

  private var inlineStages: FrameTailInlineStageRenderer {
    FrameTailInlineStageRenderer(
      layoutEngine: layoutEngine,
      semanticExtractor: semanticExtractor,
      drawExtractor: drawExtractor,
      rasterizer: rasterizer
    )
  }

  func retainedInput(
    invalidatedIdentities: Set<Identity>
  ) -> FrameTailRetainedInput {
    workerExecutor.sync {
      retainedState.input(
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }

  func renderLayout(
    _ input: FrameTailInput,
    clock: ContinuousClock?
  ) -> FrameTailLayoutOutput {
    inlineStages.renderInlineLayoutStage(
      input,
      clock: clock,
      beforeLayout: renderHooks.withLock { $0?.beforeLayout }
    )
  }

  func renderLayoutAsync(
    _ input: FrameTailInput,
    clock: ContinuousClock?,
    cancellationToken: FrameTailJobCancellationToken? = nil
  ) async -> FrameTailLayoutOutput? {
    if containsLayoutDependentContent(input.resolved) {
      input.layoutPassContext.updateWorkMetrics {
        $0.layoutDependentMainActorFallbacks += 1
      }
    }
    guard canOffloadLayout(input) else {
      guard cancellationToken?.markStarted() ?? true else {
        return nil
      }
      return inlineStages.renderInlineLayoutStage(
        input,
        clock: clock,
        beforeLayout: renderHooks.withLock { $0?.beforeLayout }
      )
    }

    let result = await workerExecutor.timedLayoutAsync(
      clock: clock,
      cancellationToken: cancellationToken
    ) {
      self.inlineStages.renderInlineLayoutStage(
        input,
        clock: clock,
        beforeLayout: self.renderHooks.withLock { $0?.beforeLayout }
      )
    }
    guard var output = result.value else {
      return nil
    }
    output.workerEnqueueToStart = result.enqueueToStart
    output.workerCompute = result.compute
    output.ranOffMain = true
    return output
  }

  func renderRaster(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?
  ) -> FrameTailOutput {
    let result = workerExecutor.timedSync(clock: clock) {
      inlineStages.renderInlineRasterTail(
        input,
        layout: layout,
        placed: placed,
        animationOverlaySnapshot: animationOverlaySnapshot,
        clock: clock,
        beforeRaster: renderHooks.withLock { $0?.beforeRaster }
      )
    }
    var output = result.value
    output.diagnostics.workerTimings = .init(
      layoutEnqueueToStart: layout.workerEnqueueToStart,
      layoutCompute: layout.workerCompute,
      rasterEnqueueToStart: result.enqueueToStart,
      rasterCompute: result.compute
    )
    output.workerCompletedAt = result.completedAt
    return output
  }

  func renderRasterAsync(
    _ input: FrameTailInput,
    layout: FrameTailLayoutOutput,
    placed: PlacedNode,
    animationOverlaySnapshot: PlacedAnimationOverlaySnapshot,
    clock: ContinuousClock?
  ) async -> FrameTailOutput {
    let result = await workerExecutor.timedAsync(clock: clock) {
      self.inlineStages.renderInlineRasterTail(
        input,
        layout: layout,
        placed: placed,
        animationOverlaySnapshot: animationOverlaySnapshot,
        clock: clock,
        beforeRaster: self.renderHooks.withLock { $0?.beforeRaster }
      )
    }
    var output = result.value
    output.diagnostics.workerTimings = .init(
      layoutEnqueueToStart: layout.workerEnqueueToStart,
      layoutCompute: layout.workerCompute,
      rasterEnqueueToStart: result.enqueueToStart,
      rasterCompute: result.compute
    )
    output.workerCompletedAt = result.completedAt
    return output
  }

  func pruneMeasurementCache(
    keeping identities: Set<Identity>
  ) {
    workerExecutor.sync {
      layoutEngine.cache?.prune(keeping: identities)
    }
  }

  func storeCommittedFrame(
    _ artifacts: FrameArtifacts,
    baselinePlacedTree: PlacedNode
  ) {
    workerExecutor.sync {
      retainedState.storeCommittedFrame(
        artifacts,
        baselinePlacedTree: baselinePlacedTree
      )
    }
  }

  func setRenderHooks(
    _ hooks: FrameTailRenderHooks?
  ) {
    renderHooks.withLock { currentHooks in
      currentHooks = hooks
    }
  }

  func setRenderSuspensionHooks(
    _ hooks: FrameRenderSuspensionHooks?
  ) {
    suspensionHooks.withLock { currentHooks in
      currentHooks = hooks
    }
  }

  func renderSuspensionHooksSnapshot() -> FrameRenderSuspensionHooks? {
    suspensionHooks.withLock { $0 }
  }

  func runLayoutWorkerJobForCancellationTesting(
    _ operation: @escaping @Sendable () -> Void
  ) async {
    await workerExecutor.runLayoutWorkerJob(operation)
  }
}
