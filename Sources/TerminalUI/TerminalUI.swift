@_exported import Core
@_exported import View

@MainActor
private final class RetainedFrameStore {
  private var previousFrame: FrameArtifacts?

  func layoutSession(
    invalidatedIdentities: Set<Identity>
  ) -> RetainedLayoutSession {
    RetainedLayoutSession(
      previousFrame: previousFrame,
      invalidatedIdentities: invalidatedIdentities
    )
  }

  func store(_ artifacts: FrameArtifacts) {
    previousFrame = artifacts
  }
}

/// Renders authored terminal views through the full frame pipeline.
///
/// `DefaultRenderer` is the public one-shot entry point for turning a `View`
/// into `FrameArtifacts` for previews, snapshot tests, diagnostics, or custom
/// presentation.
public struct DefaultRenderer {
  public let resolver: Resolver
  public let layoutEngine: LayoutEngine
  public let semanticExtractor: SemanticExtractor
  public let drawExtractor: DrawExtractor
  public let rasterizer: Rasterizer
  public let commitPlanner: CommitPlanner
  private let imageRepository: ImageAssetRepository
  private let viewGraph: ViewGraph

  private let retainedFrames: RetainedFrameStore

  /// Creates a renderer with the supplied pipeline components.
  @MainActor
  public init(
    resolver: Resolver = .init(),
    layoutEngine: LayoutEngine = .init(cache: MeasurementCache()),
    semanticExtractor: SemanticExtractor = .init(),
    drawExtractor: DrawExtractor = .init(),
    rasterizer: Rasterizer = .init(),
    commitPlanner: CommitPlanner = .init()
  ) {
    self.resolver = resolver
    self.layoutEngine = layoutEngine
    self.semanticExtractor = semanticExtractor
    self.drawExtractor = drawExtractor
    self.rasterizer = rasterizer
    self.commitPlanner = commitPlanner
    imageRepository = sharedImageAssetRepository
    viewGraph = .init()
    retainedFrames = .init()
  }

  /// Renders `root` into complete frame artifacts.
  @MainActor
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameArtifacts {
    renderView(
      root,
      context: context,
      proposal: proposal
    )
  }

  @MainActor
  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize
  ) -> FrameArtifacts {
    let clock = ContinuousClock()

    func measurePhase<Value>(
      _ operation: () -> Value
    ) -> (Value, Duration) {
      let start = clock.now
      let value = operation()
      return (value, start.duration(to: clock.now))
    }

    var resolveContext = context
    resolveContext.imageAssetResolver = imageRepository.resolver()
    resolveContext.localActionRegistry?.reset()
    resolveContext.localKeyHandlerRegistry?.reset()
    resolveContext.localPointerHandlerRegistry?.reset()
    resolveContext.localFocusBindingRegistry?.reset()
    resolveContext.localFocusedValuesRegistry?.reset()
    resolveContext.localPreferenceObservationRegistry?.reset()
    resolveContext.hotkeyRegistry?.reset()
    resolveContext.localLifecycleRegistry?.reset()
    resolveContext.localTaskRegistry?.reset()
    viewGraph.beginFrame()
    viewGraph.invalidate(context.invalidatedIdentities)
    resolveContext.viewGraph = viewGraph
    resolveContext.observationBridge?.attachViewGraph(viewGraph)
    resolveContext.observationBridge?.beginTrackingPass()
    let wrappedRoot = ToastHostingRoot(
      content: TerminalPresentationHostingRoot(
        content: ToolbarHostingRoot(content: root)
      )
    )
    viewGraph.setRootEvaluator(rootIdentity: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    viewGraph.setEvaluator(for: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }

    let (usedSelectiveDirtyEvaluation, resolveDuration) = measurePhase {
      viewGraph.evaluateDirtyNodes()
    }
    let resolved = viewGraph.snapshot()
    if usedSelectiveDirtyEvaluation {
      resolveContext.localActionRegistry?.reset()
      resolveContext.localKeyHandlerRegistry?.reset()
      resolveContext.localPointerHandlerRegistry?.reset()
      resolveContext.localFocusBindingRegistry?.reset()
      resolveContext.localFocusedValuesRegistry?.reset()
      resolveContext.localPreferenceObservationRegistry?.reset()
      resolveContext.hotkeyRegistry?.reset()
      resolveContext.localLifecycleRegistry?.reset()
      resolveContext.localTaskRegistry?.reset()
      viewGraph.restoreRuntimeRegistrations(
        for: resolved,
        into: resolveContext.localActionRegistry,
        keyHandlerRegistry: resolveContext.localKeyHandlerRegistry,
        pointerHandlerRegistry: resolveContext.localPointerHandlerRegistry,
        focusBindingRegistry: resolveContext.localFocusBindingRegistry,
        focusedValuesRegistry: resolveContext.localFocusedValuesRegistry,
        hotkeyRegistry: resolveContext.hotkeyRegistry,
        lifecycleRegistry: resolveContext.localLifecycleRegistry,
        taskRegistry: resolveContext.localTaskRegistry,
        preferenceObservationRegistry: resolveContext.localPreferenceObservationRegistry
      )
    }
    let layoutPassContext = LayoutPassContext(
      retainedLayout: retainedFrames.layoutSession(
        invalidatedIdentities: context.invalidatedIdentities
      ),
      invalidatedIdentities: context.invalidatedIdentities
    )
    let frameContext = FrameContext(
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.invalidatedIdentities
    )
    let (measured, measureDuration) = measurePhase {
      layoutEngine.measure(
        resolved,
        proposal: proposal,
        passContext: layoutPassContext
      )
    }
    let (placed, placeDuration) = measurePhase {
      layoutEngine.place(
        resolved,
        measured: measured,
        passContext: layoutPassContext
      )
    }
    let (semantics, semanticsDuration) = measurePhase {
      semanticExtractor.extract(from: placed)
    }
    let (draw, drawDuration) = measurePhase {
      drawExtractor.extract(from: placed)
    }
    let (raster, rasterDuration) = measurePhase {
      rasterizer.rasterize(
        draw,
        minimumSize: minimumRasterSurfaceSize(for: proposal)
      )
    }
    let (commit, commitDuration) = measurePhase {
      let lifecycleEvents = viewGraph.finalizeFrame(
        rootIdentity: resolveContext.identity,
        resolved: resolved,
        placed: placed
      )
      return commitPlanner.plan(
        resolved: resolved,
        placed: placed,
        semantics: semantics,
        transaction: frameContext.transaction,
        lifecycleEvents: lifecycleEvents
      )
    }
    let phaseTimings = FramePhaseTimings(
      resolve: resolveDuration,
      measure: measureDuration,
      place: placeDuration,
      semantics: semanticsDuration,
      draw: drawDuration,
      raster: rasterDuration,
      commit: commitDuration
    )
    let diagnostics = FrameDiagnostics.summarize(
      resolved: resolved,
      measured: measured,
      placed: placed,
      semantics: semantics,
      draw: draw,
      invalidatedIdentities: frameContext.invalidatedIdentities,
      resolveWork: resolveContext.resolveWorkTracker?.workMetrics,
      layoutWork: layoutPassContext.workMetrics,
      phaseTimings: phaseTimings,
      measurementCache: layoutEngine.cache?.metrics
    )
    let artifacts = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: measured,
      placedTree: placed,
      semanticSnapshot: semantics,
      drawTree: draw,
      rasterSurface: raster,
      commitPlan: commit,
      diagnostics: diagnostics
    )

    retainedFrames.store(artifacts)
    return artifacts
  }

  private func minimumRasterSurfaceSize(
    for proposal: ProposedSize
  ) -> Size {
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
