@_exported import Core
@_exported import View
@_exported import swift_figlet_embedded_fonts

@MainActor
private final class RetainedFrameStore {
  private var previousFrameIndex: RetainedFrameIndex?
  private(set) var previousRasterSurface: RasterSurface?

  func layoutSession(
    invalidatedIdentities: Set<Identity>
  ) -> RetainedLayoutSession {
    RetainedLayoutSession(
      previousFrameIndex: previousFrameIndex,
      invalidatedIdentities: invalidatedIdentities
    )
  }

  func store(_ artifacts: FrameArtifacts) {
    previousFrameIndex = .init(frame: artifacts)
    previousRasterSurface = artifacts.rasterSurface
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
  private let frameState: FrameResolveState
  private let presentationHostState: PresentationHostState

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
    frameState = .init()
    presentationHostState = .init()
    retainedFrames = .init()
  }

  /// Renders `root` into complete frame artifacts.
  @MainActor
  public func render<V: View>(
    _ root: V,
    context: ResolveContext = .init(),
    proposal: ProposedSize = .unspecified,
    collectsDiagnostics: Bool = true
  ) -> FrameArtifacts {
    renderView(
      root,
      context: context,
      proposal: proposal,
      collectsDiagnostics: collectsDiagnostics
    )
  }

  @MainActor
  private func renderView<V: View>(
    _ root: V,
    context: ResolveContext,
    proposal: ProposedSize,
    collectsDiagnostics: Bool = true
  ) -> FrameArtifacts {
    let clock: ContinuousClock? = collectsDiagnostics ? ContinuousClock() : nil

    func measurePhase<Value>(
      _ operation: () -> Value
    ) -> (Value, Duration) {
      guard let clock else {
        return (operation(), .zero)
      }
      let start = clock.now
      let value = operation()
      return (value, start.duration(to: clock.now))
    }

    var resolveContext = context
    let runtimeRegistrations = resolveContext.runtimeRegistrations
    resolveContext.imageAssetResolver = imageRepository.resolver()
    resolveContext.frameState = frameState
    frameState.update(from: resolveContext)
    viewGraph.beginFrame()
    let canUseSelectiveEvaluation =
      frameState.selectiveEvaluationEnabled
      && !frameState.environmentRequiresRootEvaluation
      && !context.invalidatedIdentities.contains(resolveContext.identity)
    if canUseSelectiveEvaluation {
      viewGraph.invalidateAndQueueDirty(context.invalidatedIdentities)
    } else {
      viewGraph.invalidate(context.invalidatedIdentities)
    }
    resolveContext.viewGraph = viewGraph
    resolveContext.observationBridge?.attachViewGraph(viewGraph)
    resolveContext.observationBridge?.beginTrackingPass()
    let wrappedRoot = PresentationHostingRoot(
      content: root,
      hostState: presentationHostState
    )
    viewGraph.setRootEvaluator(rootIdentity: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    viewGraph.setEvaluator(for: resolveContext.identity) {
      _ = resolver.resolve(wrappedRoot, in: resolveContext)
    }
    let (_, resolveDuration): (Void, Duration)
    if canUseSelectiveEvaluation, !viewGraph.hasDirtyWork {
      // Nothing is dirty — skip evaluation entirely and reuse the
      // existing tree snapshot.  The root evaluator and registrations
      // are untouched.
      resolveDuration = .zero
    } else {
      let dirtyEvaluationPlan = viewGraph.selectiveDirtyEvaluationPlan()
      if let dirtyEvaluationPlan {
        runtimeRegistrations.removeSubtrees(
          rootedAt: dirtyEvaluationPlan.frontierIdentities
        )
      } else {
        runtimeRegistrations.resetAll()
      }

      (_, resolveDuration) = measurePhase {
        viewGraph.evaluateDirtyNodes(
          using: dirtyEvaluationPlan
        )
      }
    }
    let resolved = viewGraph.snapshot()
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
    let presentationDamage = presentationDamage(
      rootIdentity: resolveContext.identity,
      placed: placed,
      retainedLayout: layoutPassContext.retainedLayout
    )
    let (semantics, semanticsDuration) = measurePhase {
      semanticExtractor.extract(from: placed)
    }
    let (draw, drawDuration) = measurePhase {
      drawExtractor.extract(from: placed)
    }
    let (raster, rasterDuration) = measurePhase {
      rasterizer.rasterize(
        draw,
        minimumSize: minimumRasterSurfaceSize(for: proposal),
        previousSurface: retainedFrames.previousRasterSurface,
        damage: presentationDamage
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
    layoutEngine.cache?.prune(keeping: viewGraph.liveIdentitySnapshot())
    let diagnostics: FrameDiagnostics
    if collectsDiagnostics {
      let phaseTimings = FramePhaseTimings(
        resolve: resolveDuration,
        measure: measureDuration,
        place: placeDuration,
        semantics: semanticsDuration,
        draw: drawDuration,
        raster: rasterDuration,
        commit: commitDuration
      )
      diagnostics = FrameDiagnostics.summarize(
        resolved: resolved,
        measured: measured,
        placed: placed,
        semantics: semantics,
        draw: draw,
        invalidatedIdentities: frameContext.invalidatedIdentities,
        resolveWork: resolveContext.resolveWorkTracker?.snapshot,
        layoutWork: layoutPassContext.workMetrics,
        phaseTimings: phaseTimings,
        measurementCache: layoutEngine.cache?.metrics
      )
    } else {
      diagnostics = .init()
    }
    let artifacts = FrameArtifacts(
      resolvedTree: resolved,
      measuredTree: measured,
      placedTree: placed,
      semanticSnapshot: semantics,
      drawTree: draw,
      rasterSurface: raster,
      presentationDamage: presentationDamage,
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

  private func presentationDamage(
    rootIdentity: Identity,
    placed: PlacedNode,
    retainedLayout: RetainedLayoutSession?
  ) -> PresentationDamage? {
    guard let retainedLayout,
      let previousFrameIndex = retainedLayout.previousFrameIndex
    else {
      return nil
    }

    let directlyInvalidated = retainedLayout.invalidationSummary.directlyInvalidated
    guard !directlyInvalidated.isEmpty, !directlyInvalidated.contains(rootIdentity) else {
      return nil
    }

    var currentPlacedByIdentity: [Identity: PlacedNode] = [:]
    indexPlacedNodes(placed, into: &currentPlacedByIdentity)

    var dirtyRows: Set<Int> = []
    for identity in directlyInvalidated {
      guard previousFrameIndex.resolvedNode(for: identity) != nil else {
        return nil
      }
      guard
        let previousPath = placedPath(
          to: identity,
          in: previousFrameIndex.placedByIdentity
        ),
        let currentPath = placedPath(
          to: identity,
          in: currentPlacedByIdentity
        ),
        cleanSiblingBoundsAreStable(
          previousPath: previousPath,
          currentPath: currentPath
        )
      else {
        return nil
      }
      let previousPlaced = previousPath.last
      let currentPlaced = currentPath.last

      if let previousBounds = previousPlaced?.bounds {
        rows(for: previousBounds, into: &dirtyRows)
      }
      if let currentBounds = currentPlaced?.bounds {
        rows(for: currentBounds, into: &dirtyRows)
      }
    }

    return .init(dirtyRows: dirtyRows)
  }

  private func placedPath(
    to identity: Identity,
    in index: [Identity: PlacedNode]
  ) -> [PlacedNode]? {
    var identities: [Identity] = []
    var currentIdentity: Identity? = identity

    while let current = currentIdentity {
      guard index[current] != nil else {
        return nil
      }
      identities.append(current)
      currentIdentity = current.parent
    }

    return identities.reversed().compactMap { index[$0] }
  }

  private func cleanSiblingBoundsAreStable(
    previousPath: [PlacedNode],
    currentPath: [PlacedNode]
  ) -> Bool {
    guard previousPath.count == currentPath.count, previousPath.count > 1 else {
      return previousPath.count == currentPath.count
    }

    for index in previousPath.indices.dropLast() {
      let previousAncestor = previousPath[index]
      let currentAncestor = currentPath[index]
      let dirtyChildIdentity = previousPath[index + 1].identity
      let previousChildren = previousAncestor.children
      let currentChildren = currentAncestor.children

      guard
        previousChildren.map(\.identity) == currentChildren.map(\.identity)
      else {
        return false
      }

      for (previousChild, currentChild) in zip(previousChildren, currentChildren)
      where previousChild.identity != dirtyChildIdentity {
        guard previousChild.bounds == currentChild.bounds else {
          return false
        }
      }
    }

    return true
  }

  private func indexPlacedNodes(
    _ node: PlacedNode,
    into storage: inout [Identity: PlacedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      indexPlacedNodes(child, into: &storage)
    }
  }

  private func rows(
    for bounds: Rect,
    into dirtyRows: inout Set<Int>
  ) {
    guard bounds.size.height > 0 else {
      return
    }

    let lowerBound = max(0, bounds.origin.y)
    let upperBound = max(lowerBound, bounds.origin.y + bounds.size.height)
    for row in lowerBound..<upperBound {
      dirtyRows.insert(row)
    }
  }

  /// Enables selective dirty-frontier evaluation for subsequent frames.
  /// Call after the first full render has established the tree and
  /// evaluator closures.
  @MainActor
  package func enableSelectiveEvaluation() {
    frameState.selectiveEvaluationEnabled = true
  }

  /// Forces the next render to use root evaluation regardless of whether
  /// selective evaluation would otherwise apply.
  @MainActor
  package func forceRootEvaluation() {
    frameState.forceRootEvaluation = true
  }

  @MainActor
  package func liveIdentitySnapshot() -> Set<Identity> {
    viewGraph.liveIdentitySnapshot()
  }
}
