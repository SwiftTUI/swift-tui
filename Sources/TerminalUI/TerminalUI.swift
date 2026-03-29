@_exported import Core
@_exported import View

// SAFETY: All mutable state is protected by OSAllocatedUnfairLock. The @unchecked is needed
// because Storage contains FrameArtifacts and RetainedResolveFrame which hold non-Sendable
// closures from the registry snapshots.
private final class RetainedFrameStore: @unchecked Sendable {
  private struct Storage {
    var previousFrame: FrameArtifacts?
    var previousResolveFrame: RetainedResolveFrame?
  }

  private let storage = OSAllocatedUnfairLock(uncheckedState: Storage())

  func layoutSession(
    invalidatedIdentities: Set<Identity>
  ) -> RetainedLayoutSession {
    storage.withLockUnchecked { storage in
      RetainedLayoutSession(
        previousFrame: storage.previousFrame,
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }

  func resolveSession(
    invalidatedIdentities: Set<Identity>
  ) -> ResolveReuseSession {
    storage.withLockUnchecked { storage in
      ResolveReuseSession(
        previousFrame: storage.previousResolveFrame,
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }

  func store(
    _ artifacts: FrameArtifacts,
    actionRegistry: LocalActionRegistry?,
    pointerHandlerRegistry: LocalPointerHandlerRegistry?,
    focusBindingRegistry: LocalFocusBindingRegistry?,
    focusedValuesRegistry: LocalFocusedValuesRegistry?,
    keyHandlerRegistry: LocalKeyHandlerRegistry?,
    lifecycleRegistry: LocalLifecycleRegistry?,
    taskRegistry: LocalTaskRegistry?
  ) {
    storage.withLockUnchecked { storage in
      storage.previousFrame = artifacts
      storage.previousResolveFrame = RetainedResolveFrame(
        resolvedTree: artifacts.resolvedTree,
        actionHandlers: actionRegistry?.snapshot() ?? [:],
        pointerHandlers: pointerHandlerRegistry?.snapshot() ?? [:],
        focusBindings: focusBindingRegistry?.snapshot() ?? [],
        focusedValues: focusedValuesRegistry?.snapshot() ?? [],
        keyHandlers: keyHandlerRegistry?.snapshot() ?? [:],
        lifecycleHandlers: lifecycleRegistry?.snapshot() ?? .init(),
        taskRegistrations: taskRegistry?.snapshot() ?? [:]
      )
    }
  }

  func latestResolvedTreeIndex() -> ResolvedTreeIndex? {
    storage.withLockUnchecked { storage in
      storage.previousResolveFrame?.resolvedTreeIndex
    }
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

  private let retainedFrames: RetainedFrameStore

  /// Creates a renderer with the supplied pipeline components.
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
    retainedFrames = .init()
  }

  /// Renders `root` into complete frame artifacts.
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified
  ) -> FrameArtifacts {
    render(
      root,
      context: context,
      proposal: proposal,
      previousLifecycleState: nil
    )
  }

  package func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified,
    previousLifecycleState: CommittedLifecycleState?
  ) -> FrameArtifacts {
    renderView(
      root,
      context: context,
      proposal: proposal,
      previousLifecycleState: previousLifecycleState
    )
  }

  package func latestResolvedTreeIndex() -> ResolvedTreeIndex? {
    retainedFrames.latestResolvedTreeIndex()
  }

  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    previousLifecycleState: CommittedLifecycleState?
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
    resolveContext.resolveReuseSession = retainedFrames.resolveSession(
      invalidatedIdentities: context.invalidatedIdentities
    )

    let (resolved, resolveDuration) = measurePhase {
      resolver.resolve(root, in: resolveContext)
    }
    let layoutPassContext = LayoutPassContext(
      retainedLayout: retainedFrames.layoutSession(
        invalidatedIdentities: context.invalidatedIdentities
      )
    )
    let frameContext = FrameContext(
      environment: context.environment,
      transaction: context.transaction,
      invalidatedIdentities: context.invalidatedIdentities,
      previousLifecycleState: previousLifecycleState
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
      rasterizer.rasterize(draw)
    }
    let (commit, commitDuration) = measurePhase {
      commitPlanner.plan(
        resolved: resolved,
        semantics: semantics,
        transaction: frameContext.transaction,
        previousLifecycleState: frameContext.previousLifecycleState
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
      resolveWork: resolveContext.resolveReuseSession?.workMetrics,
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

    retainedFrames.store(
      artifacts,
      actionRegistry: resolveContext.localActionRegistry,
      pointerHandlerRegistry: resolveContext.localPointerHandlerRegistry,
      focusBindingRegistry: resolveContext.localFocusBindingRegistry,
      focusedValuesRegistry: resolveContext.localFocusedValuesRegistry,
      keyHandlerRegistry: resolveContext.localKeyHandlerRegistry,
      lifecycleRegistry: resolveContext.localLifecycleRegistry,
      taskRegistry: resolveContext.localTaskRegistry
    )
    return artifacts
  }
}
