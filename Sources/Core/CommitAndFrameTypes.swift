/// A scheduling priority for lifecycle-owned tasks.
public enum TaskPriority: String, Equatable, Sendable {
  case userInitiated
  case high
  case medium
  case low
  case background
}

/// Identifies a lifecycle-owned task.
public struct TaskDescriptor: Equatable, Sendable {
  public var id: String
  public var priority: TaskPriority

  /// Creates a task descriptor.
  public init(id: String, priority: TaskPriority) {
    self.id = id
    self.priority = priority
  }
}

/// A lifecycle operation emitted during commit planning.
public enum LifecycleCommitOperation: Equatable, Sendable {
  case appear(handlerIDs: [String])
  case disappear(handlerIDs: [String])
  case taskStart(TaskDescriptor)
  case taskCancel(TaskDescriptor)
}

/// A single lifecycle operation emitted for one identity.
public struct LifecycleCommitEntry: Equatable, Sendable {
  public var identity: Identity
  public var operation: LifecycleCommitOperation

  public init(
    identity: Identity,
    operation: LifecycleCommitOperation
  ) {
    self.identity = identity
    self.operation = operation
  }
}

/// Records a handler that must be installed for the committed frame.
public struct HandlerInstallation: Equatable, Sendable {
  public var handlerID: RouteID

  public init(handlerID: RouteID) {
    self.handlerID = handlerID
  }
}

/// The runtime-facing result of the commit phase.
public struct CommitPlan: Equatable, Sendable {
  public var transaction: TransactionSnapshot
  public var semanticSnapshot: SemanticSnapshot
  public var lifecycle: [LifecycleCommitEntry]
  public var handlerInstallations: [HandlerInstallation]

  public init(
    transaction: TransactionSnapshot = .init(),
    semanticSnapshot: SemanticSnapshot = .init(),
    lifecycle: [LifecycleCommitEntry] = [],
    handlerInstallations: [HandlerInstallation] = []
  ) {
    self.transaction = transaction
    self.semanticSnapshot = semanticSnapshot
    self.lifecycle = lifecycle
    self.handlerInstallations = handlerInstallations
  }
}

/// Summary statistics for the retained measurement cache.
public struct MeasurementCacheMetrics: Equatable, Sendable {
  public var generation: Int
  public var entries: Int
  public var lookups: Int
  public var hits: Int
  public var misses: Int
  public var stores: Int

  public init(
    generation: Int = 0,
    entries: Int = 0,
    lookups: Int = 0,
    hits: Int = 0,
    misses: Int = 0,
    stores: Int = 0
  ) {
    self.generation = generation
    self.entries = entries
    self.lookups = lookups
    self.hits = hits
    self.misses = misses
    self.stores = stores
  }
}

package struct InvalidationSummary: Equatable, Sendable {
  package let directlyInvalidated: Set<Identity>
  package let identitiesWithInvalidatedDescendants: Set<Identity>

  package init(
    invalidatedIdentities: Set<Identity>
  ) {
    directlyInvalidated = invalidatedIdentities

    var identitiesWithInvalidatedDescendants: Set<Identity> = []
    for invalidatedIdentity in invalidatedIdentities {
      var ancestor = invalidatedIdentity.parent
      while let current = ancestor {
        identitiesWithInvalidatedDescendants.insert(current)
        ancestor = current.parent
      }
    }
    self.identitiesWithInvalidatedDescendants = identitiesWithInvalidatedDescendants
  }

  package var isEmpty: Bool {
    directlyInvalidated.isEmpty
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    directlyInvalidated.contains(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    identitiesWithInvalidatedDescendants.contains(identity)
  }

  package func hasInvalidatedAncestor(
    of identity: Identity
  ) -> Bool {
    var ancestor = identity.parent
    while let current = ancestor {
      if directlyInvalidated.contains(current) {
        return true
      }
      ancestor = current.parent
    }
    return false
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    isDirectlyInvalidated(identity)
      || containsInvalidatedDescendant(of: identity)
      || hasInvalidatedAncestor(of: identity)
  }
}

package struct ResolveWorkMetrics: Equatable, Sendable {
  package var resolvedNodesComputed: Int
  package var resolvedNodesReused: Int

  package init(
    resolvedNodesComputed: Int = 0,
    resolvedNodesReused: Int = 0
  ) {
    self.resolvedNodesComputed = resolvedNodesComputed
    self.resolvedNodesReused = resolvedNodesReused
  }
}

package struct LayoutWorkMetrics: Equatable, Sendable {
  package var measuredNodesComputed: Int
  package var measuredNodesReused: Int
  package var placedNodesComputed: Int
  package var placedNodesReused: Int

  package init(
    measuredNodesComputed: Int = 0,
    measuredNodesReused: Int = 0,
    placedNodesComputed: Int = 0,
    placedNodesReused: Int = 0
  ) {
    self.measuredNodesComputed = measuredNodesComputed
    self.measuredNodesReused = measuredNodesReused
    self.placedNodesComputed = placedNodesComputed
    self.placedNodesReused = placedNodesReused
  }
}

package struct ScrollViewportContext: Equatable, Sendable {
  package var axes: AxisSet
  package var viewportRect: Rect
  package var contentOffset: Point

  package init(
    axes: AxisSet,
    viewportRect: Rect,
    contentOffset: Point
  ) {
    self.axes = axes
    self.viewportRect = viewportRect
    self.contentOffset = contentOffset
  }
}

package struct RetainedFrameIndex: Sendable {
  package let resolvedByIdentity: [Identity: ResolvedNode]
  package let measuredByIdentity: [Identity: MeasuredNode]
  package let placedByIdentity: [Identity: PlacedNode]

  package init(frame: FrameArtifacts) {
    var resolvedByIdentity: [Identity: ResolvedNode] = [:]
    Self.index(frame.resolvedTree, into: &resolvedByIdentity)
    self.resolvedByIdentity = resolvedByIdentity

    var measuredByIdentity: [Identity: MeasuredNode] = [:]
    Self.index(frame.measuredTree, into: &measuredByIdentity)
    self.measuredByIdentity = measuredByIdentity

    var placedByIdentity: [Identity: PlacedNode] = [:]
    Self.index(frame.placedTree, into: &placedByIdentity)
    self.placedByIdentity = placedByIdentity
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    resolvedByIdentity[identity]
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    measuredByIdentity[identity]
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    placedByIdentity[identity]
  }

  private static func index(
    _ node: ResolvedNode,
    into storage: inout [Identity: ResolvedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      index(child, into: &storage)
    }
  }

  private static func index(
    _ node: MeasuredNode,
    into storage: inout [Identity: MeasuredNode]
  ) {
    storage[node.identity] = node
    for child in node.childMeasurements {
      index(child, into: &storage)
    }
  }

  private static func index(
    _ node: PlacedNode,
    into storage: inout [Identity: PlacedNode]
  ) {
    storage[node.identity] = node
    for child in node.children {
      index(child, into: &storage)
    }
  }
}

package struct RetainedInvalidationSummary: Sendable {
  private let base: InvalidationSummary
  package let identitiesWithSyntheticInvalidatedAncestors: Set<Identity>
  package let affectedIndexedChildSourceRoots: Set<Identity>

  package var directlyInvalidated: Set<Identity> {
    base.directlyInvalidated
  }

  package var identitiesWithInvalidatedDescendants: Set<Identity> {
    base.identitiesWithInvalidatedDescendants
  }

  package init(
    invalidatedIdentities: Set<Identity>,
    previousFrameIndex: RetainedFrameIndex?
  ) {
    let base = InvalidationSummary(
      invalidatedIdentities: invalidatedIdentities
    )
    self.base = base

    guard let previousFrameIndex else {
      identitiesWithSyntheticInvalidatedAncestors = []
      affectedIndexedChildSourceRoots = []
      return
    }

    let previousResolvedIdentities = Set(previousFrameIndex.resolvedByIdentity.keys)
    let syntheticInvalidatedIdentities = invalidatedIdentities.subtracting(previousResolvedIdentities)

    var identitiesWithSyntheticInvalidatedAncestors: Set<Identity> = []
    if !syntheticInvalidatedIdentities.isEmpty {
      for identity in previousResolvedIdentities {
        var ancestor = identity.parent
        while let current = ancestor {
          if syntheticInvalidatedIdentities.contains(current) {
            identitiesWithSyntheticInvalidatedAncestors.insert(identity)
            break
          }
          ancestor = current.parent
        }
      }
    }
    self.identitiesWithSyntheticInvalidatedAncestors = identitiesWithSyntheticInvalidatedAncestors

    var affectedIndexedChildSourceRoots: Set<Identity> = []
    if !invalidatedIdentities.isEmpty {
      for resolvedNode in previousFrameIndex.resolvedByIdentity.values {
        guard let source = resolvedNode.indexedChildSource else {
          continue
        }
        if base.intersectsSubtree(at: source.identityRoot) {
          affectedIndexedChildSourceRoots.insert(source.identityRoot)
        }
      }
    }
    self.affectedIndexedChildSourceRoots = affectedIndexedChildSourceRoots
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    base.isDirectlyInvalidated(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    base.containsInvalidatedDescendant(of: identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    identitiesWithSyntheticInvalidatedAncestors.contains(identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    affectedIndexedChildSourceRoots.contains(identityRoot)
  }

  package func intersectsSubtree(
    at identity: Identity
  ) -> Bool {
    base.intersectsSubtree(at: identity)
  }
}

package struct RetainedLayoutSession: Sendable {
  package var invalidatedIdentities: Set<Identity> {
    didSet {
      invalidationSummary = .init(
        invalidatedIdentities: invalidatedIdentities,
        previousFrameIndex: previousFrameIndex
      )
    }
  }
  package let previousFrameIndex: RetainedFrameIndex?
  package var invalidationSummary: RetainedInvalidationSummary

  package init(
    previousFrameIndex: RetainedFrameIndex?,
    invalidatedIdentities: Set<Identity>
  ) {
    self.invalidatedIdentities = invalidatedIdentities
    self.previousFrameIndex = previousFrameIndex
    invalidationSummary = RetainedInvalidationSummary(
      invalidatedIdentities: invalidatedIdentities,
      previousFrameIndex: previousFrameIndex
    )
  }

  package func resolvedNode(
    for identity: Identity
  ) -> ResolvedNode? {
    previousFrameIndex?.resolvedNode(for: identity)
  }

  package func measuredNode(
    for identity: Identity
  ) -> MeasuredNode? {
    previousFrameIndex?.measuredNode(for: identity)
  }

  package func placedNode(
    for identity: Identity
  ) -> PlacedNode? {
    previousFrameIndex?.placedNode(for: identity)
  }

  package func invalidationAffectsSubtree(
    at identity: Identity
  ) -> Bool {
    invalidationSummary.intersectsSubtree(at: identity)
  }

  package func isDirectlyInvalidated(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.isDirectlyInvalidated(identity)
  }

  package func hasSyntheticInvalidatedAncestor(
    _ identity: Identity
  ) -> Bool {
    invalidationSummary.hasSyntheticInvalidatedAncestor(identity)
  }

  package func containsInvalidatedDescendant(
    of identity: Identity
  ) -> Bool {
    invalidationSummary.containsInvalidatedDescendant(of: identity)
  }

  package func affectsIndexedChildSource(
    root identityRoot: Identity
  ) -> Bool {
    invalidationSummary.affectsIndexedChildSource(root: identityRoot)
  }
}

// SAFETY: Created per-frame and exclusively accessed during the layout phase on
// a single thread. `nonisolated(unsafe)` narrows the unsafety to the mutable
// members that accumulate per-pass work.
package final class LayoutPassContext: Sendable {
  package let retainedLayout: RetainedLayoutSession?
  package let invalidatedIdentities: Set<Identity>
  nonisolated(unsafe) package var scrollViewportContext: ScrollViewportContext?
  nonisolated(unsafe) package var workMetrics: LayoutWorkMetrics

  package init(
    retainedLayout: RetainedLayoutSession? = nil,
    invalidatedIdentities: Set<Identity> = [],
    scrollViewportContext: ScrollViewportContext? = nil
  ) {
    self.retainedLayout = retainedLayout
    self.invalidatedIdentities = invalidatedIdentities
    self.scrollViewportContext = scrollViewportContext
    workMetrics = .init()
  }
}

/// Phase-by-phase timing summaries captured while rendering one frame.
public struct FramePhaseTimings: Equatable, Sendable {
  public var resolve: Duration
  public var measure: Duration
  public var place: Duration
  public var semantics: Duration
  public var draw: Duration
  public var raster: Duration
  public var commit: Duration

  public init(
    resolve: Duration = .zero,
    measure: Duration = .zero,
    place: Duration = .zero,
    semantics: Duration = .zero,
    draw: Duration = .zero,
    raster: Duration = .zero,
    commit: Duration = .zero
  ) {
    self.resolve = resolve
    self.measure = measure
    self.place = place
    self.semantics = semantics
    self.draw = draw
    self.raster = raster
    self.commit = commit
  }

  public var total: Duration {
    resolve
      + measure
      + place
      + semantics
      + draw
      + raster
      + commit
  }
}

/// Diagnostic counters and summaries for one rendered frame.
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
  public var drawNodeCount: Int
  public var interactionRegionCount: Int
  public var focusRegionCount: Int
  public var scrollRouteCount: Int
  public var selectionRouteCount: Int
  public var phaseTimings: FramePhaseTimings?
  public var measurementCache: MeasurementCacheMetrics?

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
    drawNodeCount: Int = 0,
    interactionRegionCount: Int = 0,
    focusRegionCount: Int = 0,
    scrollRouteCount: Int = 0,
    selectionRouteCount: Int = 0,
    phaseTimings: FramePhaseTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil
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
    self.drawNodeCount = drawNodeCount
    self.interactionRegionCount = interactionRegionCount
    self.focusRegionCount = focusRegionCount
    self.scrollRouteCount = scrollRouteCount
    self.selectionRouteCount = selectionRouteCount
    self.phaseTimings = phaseTimings
    self.measurementCache = measurementCache
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

package struct PresentationDamage: Equatable, Sendable {
  package var dirtyRows: Set<Int>

  package init(
    dirtyRows: Set<Int> = []
  ) {
    self.dirtyRows = dirtyRows
  }
}

/// The complete output of one rendered frame.
public struct FrameArtifacts: Equatable, Sendable {
  public var resolvedTree: ResolvedNode
  public var measuredTree: MeasuredNode
  public var placedTree: PlacedNode
  public var semanticSnapshot: SemanticSnapshot
  public var drawTree: DrawNode
  public var rasterSurface: RasterSurface
  package var presentationDamage: PresentationDamage?
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
    phaseTimings: FramePhaseTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil
  ) -> Self {
    Self(
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
      drawNodeCount: draw.subtreeNodeCount,
      interactionRegionCount: semantics.interactionRegions.count,
      focusRegionCount: semantics.focusRegions.count,
      scrollRouteCount: semantics.scrollRoutes.count,
      selectionRouteCount: semantics.selectionRoutes.count,
      phaseTimings: phaseTimings,
      measurementCache: measurementCache
    )
  }
}
