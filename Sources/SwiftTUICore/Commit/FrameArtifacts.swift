public struct FrameDiagnostics: Equatable, Sendable {
  public var proposal: ProposedSize
  public var invalidatedIdentities: Set<Identity>
  public var resolvedNodeCount: Int
  public var measuredNodeCount: Int
  public var placedNodeCount: Int
  public var resolvedNodesComputed: Int
  public var resolvedNodesReused: Int
  public var measuredNodesComputed: Int
  public var measuredNodesReused: Int
  public var placedNodesComputed: Int
  public var placedNodesReused: Int
  public var layoutDependentRealizations: Int
  public var layoutDependentRealizationCacheHits: Int
  public var layoutDependentMainActorFallbacks: Int
  public var drawNodeCount: Int
  public var interactionRegionCount: Int
  public var focusRegionCount: Int
  public var scrollRouteCount: Int
  public var selectionRouteCount: Int
  public var presentationDamage: PresentationDamageDiagnostics?
  public var phaseTimings: FramePhaseTimings?
  public var renderGenerations: FrameRenderGenerations
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?
  public var measurementCache: MeasurementCacheMetrics?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: Identity?
  public var runtimeRegistrations: RuntimeRegistrationDiagnostics
  public var runtimeIssues: [RuntimeIssue]
  public var dropEligibilityBlockers: Set<FrameDropEligibility.Blocker>
  package var geometryResolutionDiagnostics: GeometryResolutionDiagnostics = .init()

  public init(
    proposal: ProposedSize = .unspecified,
    invalidatedIdentities: Set<Identity> = [],
    resolvedNodeCount: Int = 0,
    measuredNodeCount: Int = 0,
    placedNodeCount: Int = 0,
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0,
    measuredNodesComputed: Int = 0,
    measuredNodesReused: Int = 0,
    placedNodesComputed: Int = 0,
    placedNodesReused: Int = 0,
    layoutDependentRealizations: Int = 0,
    layoutDependentRealizationCacheHits: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    drawNodeCount: Int = 0,
    interactionRegionCount: Int = 0,
    focusRegionCount: Int = 0,
    scrollRouteCount: Int = 0,
    selectionRouteCount: Int = 0,
    presentationDamage: PresentationDamageDiagnostics? = nil,
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil,
    customLayoutFallbackCount: Int = 0,
    firstCustomLayoutFallbackIdentity: Identity? = nil,
    runtimeRegistrations: RuntimeRegistrationDiagnostics = .init(),
    runtimeIssues: [RuntimeIssue] = [],
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker> = []
  ) {
    self.proposal = proposal
    self.invalidatedIdentities = invalidatedIdentities
    self.resolvedNodeCount = resolvedNodeCount
    self.measuredNodeCount = measuredNodeCount
    self.placedNodeCount = placedNodeCount
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
    self.measuredNodesComputed = measuredNodesComputed
    self.measuredNodesReused = measuredNodesReused
    self.placedNodesComputed = placedNodesComputed
    self.placedNodesReused = placedNodesReused
    self.layoutDependentRealizations = layoutDependentRealizations
    self.layoutDependentRealizationCacheHits = layoutDependentRealizationCacheHits
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.drawNodeCount = drawNodeCount
    self.interactionRegionCount = interactionRegionCount
    self.focusRegionCount = focusRegionCount
    self.scrollRouteCount = scrollRouteCount
    self.selectionRouteCount = selectionRouteCount
    self.presentationDamage = presentationDamage
    self.phaseTimings = phaseTimings
    self.renderGenerations = renderGenerations
    self.workerTimings = workerTimings
    self.mainActorTimings = mainActorTimings
    self.measurementCache = measurementCache
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.firstCustomLayoutFallbackIdentity = firstCustomLayoutFallbackIdentity
    self.runtimeRegistrations = runtimeRegistrations
    self.runtimeIssues = runtimeIssues
    self.dropEligibilityBlockers = dropEligibilityBlockers
  }
}

/// Per-frame inputs shared across pipeline phases.
public struct FrameContext: Equatable, Sendable {
  public var environment: EnvironmentSnapshot
  public var transaction: TransactionSnapshot
  public var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities
      )
    }
  }
  package var invalidationSummary: InvalidationSummary
  public var timestamp: MonotonicInstant
  package var animationRequest: AnimationRequest
  package var animationBatchID: AnimationBatchID?

  /// Creates a frame context.
  public init(
    environment: EnvironmentSnapshot = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    timestamp: MonotonicInstant = .now()
  ) {
    self.environment = environment
    self.transaction = transaction
    self.invalidatedIdentities = invalidatedIdentities
    invalidationSummary = .init(
      invalidatedIdentities: invalidatedIdentities
    )
    self.timestamp = timestamp
    self.animationRequest = .inherit
    self.animationBatchID = nil
  }

  /// Creates a frame context with an animation request.
  package init(
    environment: EnvironmentSnapshot = .init(),
    transaction: TransactionSnapshot = .init(),
    invalidatedIdentities: Set<Identity> = [],
    timestamp: MonotonicInstant = .now(),
    animationRequest: AnimationRequest,
    animationBatchID: AnimationBatchID? = nil
  ) {
    self.environment = environment
    self.transaction = transaction
    self.invalidatedIdentities = invalidatedIdentities
    invalidationSummary = .init(
      invalidatedIdentities: invalidatedIdentities
    )
    self.timestamp = timestamp
    self.animationRequest = animationRequest
    self.animationBatchID = animationBatchID
  }

  /// Returns whether `identity` is directly invalidated in this frame.
  public func isInvalidated(_ identity: Identity) -> Bool {
    invalidatedIdentities.contains(identity)
  }

  /// Returns whether the invalidation set intersects the subtree rooted at
  /// `identity`.
  public func invalidationAffectsSubtree(
    at identity: Identity
  ) -> Bool {
    invalidationSummary.intersectsSubtree(at: identity)
  }
}
public struct FrameArtifacts: Equatable, Sendable {
  public var resolvedTree: ResolvedNode
  public var measuredTree: MeasuredNode
  public var placedTree: PlacedNode
  public var semanticSnapshot: SemanticSnapshot
  public var drawTree: DrawNode
  public var rasterSurface: RasterSurface
  /// Optional retained-frame presentation damage.
  ///
  /// A non-`nil` value is an advisory hint for presentation surfaces that retain
  /// the previous committed frame and can redraw only changed rows or ranges.
  /// A `nil` value means the frame must be treated as a full repaint.
  public var presentationDamage: PresentationDamage?
  /// Identities whose ``DrawNode`` had a non-empty visible rect after
  /// all ancestor clip bounds were applied during rasterization.
  ///
  /// The runtime retains this set as a geometric visibility signal for
  /// diagnostics and scheduling policy. Animation deadlines are no longer
  /// suppressed solely because an identity is absent from this set; the
  /// scheduler may still use it to understand whether an animating subtree
  /// painted any cells in the current frame.
  ///
  /// Note: this is a geometric predicate (would the identity paint any
  /// cells given the current clip), not an observation of incremental
  /// repaint behavior.  An identity that is visible but happens to
  /// fall outside ``presentationDamage`` for this particular frame is
  /// still recorded here.
  package var drawnIdentities: Set<Identity>
  public var commitPlan: CommitPlan
  public var diagnostics: FrameDiagnostics

  /// Creates a full frame artifact bundle.
  public init(
    resolvedTree: ResolvedNode,
    measuredTree: MeasuredNode,
    placedTree: PlacedNode,
    semanticSnapshot: SemanticSnapshot,
    drawTree: DrawNode,
    rasterSurface: RasterSurface,
    commitPlan: CommitPlan,
    diagnostics: FrameDiagnostics = .init()
  ) {
    self.resolvedTree = resolvedTree
    self.measuredTree = measuredTree
    self.placedTree = placedTree
    self.semanticSnapshot = semanticSnapshot
    self.drawTree = drawTree
    self.rasterSurface = rasterSurface
    presentationDamage = nil
    drawnIdentities = []
    self.commitPlan = commitPlan
    self.diagnostics = diagnostics
  }

  package init(
    resolvedTree: ResolvedNode,
    measuredTree: MeasuredNode,
    placedTree: PlacedNode,
    semanticSnapshot: SemanticSnapshot,
    drawTree: DrawNode,
    rasterSurface: RasterSurface,
    presentationDamage: PresentationDamage?,
    drawnIdentities: Set<Identity> = [],
    commitPlan: CommitPlan,
    diagnostics: FrameDiagnostics = .init()
  ) {
    self.resolvedTree = resolvedTree
    self.measuredTree = measuredTree
    self.placedTree = placedTree
    self.semanticSnapshot = semanticSnapshot
    self.drawTree = drawTree
    self.rasterSurface = rasterSurface
    self.presentationDamage = presentationDamage
    self.drawnIdentities = drawnIdentities
    self.commitPlan = commitPlan
    self.diagnostics = diagnostics
  }
}

extension FrameDiagnostics {
  package static func summarize(
    resolved: ResolvedNode,
    measured: MeasuredNode,
    placed: PlacedNode,
    semantics: SemanticSnapshot,
    draw: DrawNode,
    invalidatedIdentities: Set<Identity> = [],
    resolveWork: ResolveWorkMetrics? = nil,
    layoutWork: LayoutWorkMetrics? = nil,
    presentationDamage: PresentationDamage? = nil,
    presentationSurfaceWidth: Int = 0,
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil,
    runtimeIssues: [RuntimeIssue] = [],
    dropEligibilityBlockers: Set<FrameDropEligibility.Blocker> = []
  ) -> Self {
    let customLayoutFallback = customLayoutFallbackSummary(resolved)
    var diagnostics = Self(
      proposal: measured.proposal,
      invalidatedIdentities: invalidatedIdentities,
      resolvedNodeCount: resolved.subtreeNodeCount,
      measuredNodeCount: measured.subtreeNodeCount,
      placedNodeCount: placed.subtreeNodeCount,
      resolvedNodesComputed: resolveWork?.resolvedNodesComputed ?? 0,
      resolvedNodesReused: resolveWork?.resolvedNodesReused ?? 0,
      measuredNodesComputed: layoutWork?.measuredNodesComputed ?? 0,
      measuredNodesReused: layoutWork?.measuredNodesReused ?? 0,
      placedNodesComputed: layoutWork?.placedNodesComputed ?? 0,
      placedNodesReused: layoutWork?.placedNodesReused ?? 0,
      layoutDependentRealizations: layoutWork?.layoutDependentRealizations ?? 0,
      layoutDependentRealizationCacheHits: layoutWork?.layoutDependentRealizationCacheHits ?? 0,
      layoutDependentMainActorFallbacks: layoutWork?.layoutDependentMainActorFallbacks ?? 0,
      drawNodeCount: draw.subtreeNodeCount,
      interactionRegionCount: semantics.interactionRegions.count,
      focusRegionCount: semantics.focusRegions.count,
      scrollRouteCount: semantics.scrollRoutes.count,
      selectionRouteCount: semantics.selectionRoutes.count,
      presentationDamage: presentationDamage.map {
        .init(
          damage: $0,
          surfaceWidth: presentationSurfaceWidth
        )
      },
      phaseTimings: phaseTimings,
      renderGenerations: renderGenerations,
      workerTimings: workerTimings,
      mainActorTimings: mainActorTimings,
      measurementCache: measurementCache,
      customLayoutFallbackCount: customLayoutFallback.count,
      firstCustomLayoutFallbackIdentity: customLayoutFallback.firstIdentity,
      runtimeIssues: runtimeIssues,
      dropEligibilityBlockers: dropEligibilityBlockers
    )
    diagnostics.geometryResolutionDiagnostics =
      layoutWork?.geometryResolutionDiagnostics ?? .init()
    return diagnostics
  }

  private static func customLayoutFallbackSummary(
    _ node: ResolvedNode
  ) -> (count: Int, firstIdentity: Identity?) {
    var count = 0
    var firstIdentity: Identity?
    collectCustomLayoutFallbacks(
      in: node,
      count: &count,
      firstIdentity: &firstIdentity
    )
    return (count, firstIdentity)
  }

  private static func collectCustomLayoutFallbacks(
    in node: ResolvedNode,
    count: inout Int,
    firstIdentity: inout Identity?
  ) {
    if case .custom(let handle) = node.layoutBehavior,
      !handle.canRunOnWorker
    {
      count += 1
      if firstIdentity == nil {
        firstIdentity = node.identity
      }
    }

    if let workerChildren = node.indexedChildSource?.workerResolvedChildren {
      for child in workerChildren {
        collectCustomLayoutFallbacks(
          in: child,
          count: &count,
          firstIdentity: &firstIdentity
        )
      }
    }

    for child in node.children {
      collectCustomLayoutFallbacks(
        in: child,
        count: &count,
        firstIdentity: &firstIdentity
      )
    }
  }
}
