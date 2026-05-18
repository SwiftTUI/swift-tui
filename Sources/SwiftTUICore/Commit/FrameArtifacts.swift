import Synchronization

private struct FrameDiagnosticsSummaryDebugKey: Hashable, Sendable {
  var epoch: UInt64
  var id: UInt64
}

private enum FrameDiagnosticsSummaryComputationCounter {
  static let epoch = Atomic<UInt64>(0)
  static let nextID = Atomic<UInt64>(0)
  static let count = Atomic<Int>(0)
  static let seen = Mutex<Set<FrameDiagnosticsSummaryDebugKey>>([])
}

public struct FrameDiagnosticInput: Equatable, Sendable {
  public var proposal: ProposedSize
  public var invalidatedIdentities: Set<Identity>

  public init(
    proposal: ProposedSize = .unspecified,
    invalidatedIdentities: Set<Identity> = []
  ) {
    self.proposal = proposal
    self.invalidatedIdentities = invalidatedIdentities
  }
}

public struct FrameDiagnosticCounts: Equatable, Sendable {
  public var resolvedNodes: Int
  public var measuredNodes: Int
  public var placedNodes: Int
  public var drawNodes: Int
  public var interactionRegions: Int
  public var focusRegions: Int
  public var scrollRoutes: Int
  public var selectionRoutes: Int

  public init(
    resolvedNodes: Int = 0,
    measuredNodes: Int = 0,
    placedNodes: Int = 0,
    drawNodes: Int = 0,
    interactionRegions: Int = 0,
    focusRegions: Int = 0,
    scrollRoutes: Int = 0,
    selectionRoutes: Int = 0
  ) {
    self.resolvedNodes = resolvedNodes
    self.measuredNodes = measuredNodes
    self.placedNodes = placedNodes
    self.drawNodes = drawNodes
    self.interactionRegions = interactionRegions
    self.focusRegions = focusRegions
    self.scrollRoutes = scrollRoutes
    self.selectionRoutes = selectionRoutes
  }
}

public struct FrameDiagnosticWork: Equatable, Sendable {
  public var resolvedNodesComputed: Int
  public var resolvedNodesReused: Int
  public var measuredNodesComputed: Int
  public var measuredNodesReused: Int
  public var placedNodesComputed: Int
  public var placedNodesReused: Int
  public var layoutDependentRealizations: Int
  public var layoutDependentRealizationCacheHits: Int
  public var layoutDependentMainActorFallbacks: Int
  public var measurementCache: MeasurementCacheMetrics?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: Identity?

  public init(
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0,
    measuredNodesComputed: Int = 0,
    measuredNodesReused: Int = 0,
    placedNodesComputed: Int = 0,
    placedNodesReused: Int = 0,
    layoutDependentRealizations: Int = 0,
    layoutDependentRealizationCacheHits: Int = 0,
    layoutDependentMainActorFallbacks: Int = 0,
    measurementCache: MeasurementCacheMetrics? = nil,
    customLayoutFallbackCount: Int = 0,
    firstCustomLayoutFallbackIdentity: Identity? = nil
  ) {
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
    self.measuredNodesComputed = measuredNodesComputed
    self.measuredNodesReused = measuredNodesReused
    self.placedNodesComputed = placedNodesComputed
    self.placedNodesReused = placedNodesReused
    self.layoutDependentRealizations = layoutDependentRealizations
    self.layoutDependentRealizationCacheHits = layoutDependentRealizationCacheHits
    self.layoutDependentMainActorFallbacks = layoutDependentMainActorFallbacks
    self.measurementCache = measurementCache
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.firstCustomLayoutFallbackIdentity = firstCustomLayoutFallbackIdentity
  }
}

public struct FrameDiagnosticPresentation: Equatable, Sendable {
  public var damage: PresentationDamageDiagnostics?

  public init(damage: PresentationDamageDiagnostics? = nil) {
    self.damage = damage
  }
}

public struct FrameDiagnosticTiming: Equatable, Sendable {
  public var phaseTimings: FramePhaseTimings?
  public var renderGenerations: FrameRenderGenerations
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?

  public init(
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil
  ) {
    self.phaseTimings = phaseTimings
    self.renderGenerations = renderGenerations
    self.workerTimings = workerTimings
    self.mainActorTimings = mainActorTimings
  }
}

public struct FrameDiagnosticRuntime: Equatable, Sendable {
  public var registrations: RuntimeRegistrationDiagnostics
  public var issues: [RuntimeIssue]

  public init(
    registrations: RuntimeRegistrationDiagnostics = .init(),
    issues: [RuntimeIssue] = []
  ) {
    self.registrations = registrations
    self.issues = issues
  }
}

public struct FrameDiagnosticDrop: Equatable, Sendable {
  public var eligibilityBlockers: Set<FrameDropEligibility.Blocker>

  public init(
    eligibilityBlockers: Set<FrameDropEligibility.Blocker> = []
  ) {
    self.eligibilityBlockers = eligibilityBlockers
  }
}

private struct FrameDiagnosticSummary: Equatable, Sendable {
  var counts: FrameDiagnosticCounts
  var work: FrameDiagnosticWork
}

public struct FrameDiagnostics: Sendable {
  public var input: FrameDiagnosticInput
  private var diagnosticSummary: FrameDiagnosticSummary
  private let debugSummaryID: UInt64
  public var counts: FrameDiagnosticCounts {
    get {
      Self.recordSummaryComputation(for: debugSummaryID)
      return diagnosticSummary.counts
    }
    set {
      diagnosticSummary.counts = newValue
    }
  }

  public var work: FrameDiagnosticWork {
    get {
      Self.recordSummaryComputation(for: debugSummaryID)
      return diagnosticSummary.work
    }
    set {
      diagnosticSummary.work = newValue
    }
  }

  public var presentation: FrameDiagnosticPresentation
  public var timing: FrameDiagnosticTiming
  public var runtime: FrameDiagnosticRuntime
  public var drop: FrameDiagnosticDrop
  package var geometryResolutionDiagnostics: GeometryResolutionDiagnostics = .init()

  public init(
    input: FrameDiagnosticInput = .init(),
    counts: FrameDiagnosticCounts = .init(),
    work: FrameDiagnosticWork = .init(),
    presentation: FrameDiagnosticPresentation = .init(),
    timing: FrameDiagnosticTiming = .init(),
    runtime: FrameDiagnosticRuntime = .init(),
    drop: FrameDiagnosticDrop = .init()
  ) {
    self.input = input
    self.diagnosticSummary = .init(
      counts: counts,
      work: work
    )
    self.debugSummaryID = Self.nextDebugSummaryID()
    self.presentation = presentation
    self.timing = timing
    self.runtime = runtime
    self.drop = drop
  }

  private init(
    input: FrameDiagnosticInput,
    diagnosticSummary: FrameDiagnosticSummary,
    presentation: FrameDiagnosticPresentation,
    timing: FrameDiagnosticTiming,
    runtime: FrameDiagnosticRuntime,
    drop: FrameDiagnosticDrop,
    geometryResolutionDiagnostics: GeometryResolutionDiagnostics
  ) {
    self.input = input
    self.diagnosticSummary = diagnosticSummary
    self.debugSummaryID = Self.nextDebugSummaryID()
    self.presentation = presentation
    self.timing = timing
    self.runtime = runtime
    self.drop = drop
    self.geometryResolutionDiagnostics = geometryResolutionDiagnostics
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

/// Aggregate frame product for inspection, retained reuse, and runtime handoff.
///
/// The individual phase products keep their own ownership contracts. This
/// bundle preserves the current-frame products together with diagnostics,
/// presentation hints, and the commit plan. Retained-layout indexes must use a
/// canonical baseline placed tree rather than an animation-decorated placed tree
/// when storing these artifacts for a later frame.
///
/// Field authority:
///
/// - Canonical phase products: ``resolvedTree``, ``measuredTree``,
///   ``semanticSnapshot``, ``drawTree``, and ``rasterSurface``.
/// - Decorated/baseline-sensitive projection: ``placedTree``. A current frame
///   may commit an animation-decorated placed tree, but retained-layout
///   baselines must store the canonical placement product.
/// - Advisory hints: ``presentationDamage`` and ``drawnIdentities``.
/// - Side-effect plan: ``commitPlan``.
/// - Diagnostics: ``diagnostics``.
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

extension FrameArtifacts {
  public static func == (lhs: Self, rhs: Self) -> Bool {
    lhs.resolvedTree == rhs.resolvedTree
      && lhs.measuredTree == rhs.measuredTree
      && lhs.placedTree == rhs.placedTree
      && lhs.semanticSnapshot == rhs.semanticSnapshot
      && lhs.drawTree == rhs.drawTree
      && lhs.rasterSurface == rhs.rasterSurface
      && lhs.presentationDamage == rhs.presentationDamage
      && lhs.drawnIdentities == rhs.drawnIdentities
      && lhs.commitPlan == rhs.commitPlan
  }
}

extension FrameDiagnostics {
  private static func nextDebugSummaryID() -> UInt64 {
    FrameDiagnosticsSummaryComputationCounter.nextID.wrappingAdd(1, ordering: .relaxed).newValue
  }

  package static func debugResetSummaryComputationCount() {
    FrameDiagnosticsSummaryComputationCounter.count.store(0, ordering: .relaxed)
    FrameDiagnosticsSummaryComputationCounter.seen.withLock {
      $0.removeAll(keepingCapacity: true)
    }
    _ = FrameDiagnosticsSummaryComputationCounter.epoch.wrappingAdd(1, ordering: .relaxed)
  }

  package static func debugSummaryComputationCount() -> Int {
    FrameDiagnosticsSummaryComputationCounter.count.load(ordering: .relaxed)
  }

  private static func recordSummaryComputation(for id: UInt64) {
    let epoch = FrameDiagnosticsSummaryComputationCounter.epoch.load(ordering: .relaxed)
    guard epoch != 0 else {
      return
    }
    let key = FrameDiagnosticsSummaryDebugKey(epoch: epoch, id: id)
    let inserted = FrameDiagnosticsSummaryComputationCounter.seen.withLock {
      $0.insert(key).inserted
    }
    if inserted {
      FrameDiagnosticsSummaryComputationCounter.count.wrappingAdd(1, ordering: .relaxed)
    }
  }

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
    let customLayoutFallback = resolved.customLayoutFallbackSummary
    return Self(
      input: .init(
        proposal: measured.proposal,
        invalidatedIdentities: invalidatedIdentities
      ),
      diagnosticSummary: .init(
        counts: .init(
          resolvedNodes: resolved.subtreeNodeCount,
          measuredNodes: measured.subtreeNodeCount,
          placedNodes: placed.subtreeNodeCount,
          drawNodes: draw.subtreeNodeCount,
          interactionRegions: semantics.interactionRegions.count,
          focusRegions: semantics.focusRegions.count,
          scrollRoutes: semantics.scrollRoutes.count,
          selectionRoutes: semantics.selectionRoutes.count
        ),
        work: .init(
          resolvedNodesComputed: resolveWork?.resolvedNodesComputed ?? 0,
          resolvedNodesReused: resolveWork?.resolvedNodesReused ?? 0,
          measuredNodesComputed: layoutWork?.measuredNodesComputed ?? 0,
          measuredNodesReused: layoutWork?.measuredNodesReused ?? 0,
          placedNodesComputed: layoutWork?.placedNodesComputed ?? 0,
          placedNodesReused: layoutWork?.placedNodesReused ?? 0,
          layoutDependentRealizations: layoutWork?.layoutDependentRealizations ?? 0,
          layoutDependentRealizationCacheHits:
            layoutWork?.layoutDependentRealizationCacheHits ?? 0,
          layoutDependentMainActorFallbacks:
            layoutWork?.layoutDependentMainActorFallbacks ?? 0,
          measurementCache: measurementCache,
          customLayoutFallbackCount: customLayoutFallback.count,
          firstCustomLayoutFallbackIdentity: customLayoutFallback.firstIdentity
        )),
      presentation: .init(
        damage: presentationDamage.map {
          .init(
            damage: $0,
            surfaceWidth: presentationSurfaceWidth
          )
        }
      ),
      timing: .init(
        phaseTimings: phaseTimings,
        renderGenerations: renderGenerations,
        workerTimings: workerTimings,
        mainActorTimings: mainActorTimings
      ),
      runtime: .init(issues: runtimeIssues),
      drop: .init(eligibilityBlockers: dropEligibilityBlockers),
      geometryResolutionDiagnostics:
        layoutWork?.geometryResolutionDiagnostics ?? .init()
    )
  }
}
