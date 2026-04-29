import Synchronization

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
  case change(handlerIDs: [String])
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
  /// Count of lookups that found a cached entry but evicted it because the
  /// cached `ResolvedNode` was no longer equivalent for measurement.  Kept
  /// distinct from `misses` so observability can tell a cold miss apart
  /// from a structural invalidation.
  public var invalidations: Int
  public var stores: Int

  public init(
    generation: Int = 0,
    entries: Int = 0,
    lookups: Int = 0,
    hits: Int = 0,
    misses: Int = 0,
    invalidations: Int = 0,
    stores: Int = 0
  ) {
    self.generation = generation
    self.entries = entries
    self.lookups = lookups
    self.hits = hits
    self.misses = misses
    self.invalidations = invalidations
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
  package var viewportRect: CellRect
  package var contentOffset: CellPoint

  package init(
    axes: AxisSet,
    viewportRect: CellRect,
    contentOffset: CellPoint
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
    let syntheticInvalidatedIdentities = invalidatedIdentities.subtracting(
      previousResolvedIdentities)

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

package final class LayoutPassContext: Sendable {
  private struct MutableState: Sendable {
    var scrollViewportContext: ScrollViewportContext?
    var workMetrics: LayoutWorkMetrics
    var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate]
  }

  package let retainedLayout: RetainedLayoutSession?
  package let invalidatedIdentities: Set<Identity>
  private let state: Mutex<MutableState>

  package init(
    retainedLayout: RetainedLayoutSession? = nil,
    invalidatedIdentities: Set<Identity> = [],
    scrollViewportContext: ScrollViewportContext? = nil
  ) {
    self.retainedLayout = retainedLayout
    self.invalidatedIdentities = invalidatedIdentities
    state = .init(
      .init(
        scrollViewportContext: scrollViewportContext,
        workMetrics: .init(),
        workerCustomLayoutCacheUpdates: []
      )
    )
  }

  package var scrollViewportContext: ScrollViewportContext? {
    state.withLock { $0.scrollViewportContext }
  }

  package var workMetrics: LayoutWorkMetrics {
    state.withLock { $0.workMetrics }
  }

  package var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate] {
    state.withLock { $0.workerCustomLayoutCacheUpdates }
  }

  package func updateWorkMetrics(
    _ update: (inout LayoutWorkMetrics) -> Void
  ) {
    state.withLock { update(&$0.workMetrics) }
  }

  package func recordWorkerCustomLayoutCacheUpdate(
    _ update: WorkerCustomLayoutCacheUpdate
  ) {
    state.withLock { $0.workerCustomLayoutCacheUpdates.append(update) }
  }
}

package struct WorkerCustomLayoutCacheUpdate: Sendable {
  package var identity: Identity
  private let applyHandler: @MainActor @Sendable () -> Void

  package init(
    identity: Identity,
    apply: @escaping @MainActor @Sendable () -> Void
  ) {
    self.identity = identity
    applyHandler = apply
  }

  @MainActor
  package func apply() {
    applyHandler()
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

/// Monotonic identity assigned to one renderer pass.
public struct RenderGeneration: Comparable, Equatable, Hashable, Sendable {
  public var rawValue: UInt64

  public init(_ rawValue: UInt64 = 0) {
    self.rawValue = rawValue
  }

  public static func < (lhs: Self, rhs: Self) -> Bool {
    lhs.rawValue < rhs.rawValue
  }
}

extension RenderGeneration {
  public static var zero: Self {
    Self()
  }
}

/// Generation IDs observed while rendering one frame.
public struct FrameRenderGenerations: Equatable, Sendable {
  public var render: RenderGeneration
  public var layoutInput: RenderGeneration?
  public var layoutOutput: RenderGeneration?
  public var rasterInput: RenderGeneration?
  public var rasterOutput: RenderGeneration?

  public init(
    render: RenderGeneration = .zero,
    layoutInput: RenderGeneration? = nil,
    layoutOutput: RenderGeneration? = nil,
    rasterInput: RenderGeneration? = nil,
    rasterOutput: RenderGeneration? = nil
  ) {
    self.render = render
    self.layoutInput = layoutInput
    self.layoutOutput = layoutOutput
    self.rasterInput = rasterInput
    self.rasterOutput = rasterOutput
  }
}

/// Timing summaries for work submitted to the frame-tail renderer.
public struct FrameWorkerTimings: Equatable, Sendable {
  public var layoutEnqueueToStart: Duration
  public var layoutCompute: Duration
  public var rasterEnqueueToStart: Duration
  public var rasterCompute: Duration
  public var completionToMainCommit: Duration

  public init(
    layoutEnqueueToStart: Duration = .zero,
    layoutCompute: Duration = .zero,
    rasterEnqueueToStart: Duration = .zero,
    rasterCompute: Duration = .zero,
    completionToMainCommit: Duration = .zero
  ) {
    self.layoutEnqueueToStart = layoutEnqueueToStart
    self.layoutCompute = layoutCompute
    self.rasterEnqueueToStart = rasterEnqueueToStart
    self.rasterCompute = rasterCompute
    self.completionToMainCommit = completionToMainCommit
  }
}

/// Main-actor timing summaries for one render pass.
public struct FrameMainActorTimings: Equatable, Sendable {
  public var blocked: Duration
  public var suspended: Duration

  public init(
    blocked: Duration = .zero,
    suspended: Duration = .zero
  ) {
    self.blocked = blocked
    self.suspended = suspended
  }
}

/// Diagnostic counters and summaries for one rendered frame.
public struct PresentationDamageDiagnostics: Equatable, Sendable {
  public var textRowCount: Int
  public var rangeAwareTextRowCount: Int
  public var textSpanCount: Int
  public var textCellCount: Int
  public var graphicsInvalidationCount: Int
  public var requiresFullTextRepaint: Bool
  public var requiresFullGraphicsReplay: Bool

  public init(
    textRowCount: Int = 0,
    rangeAwareTextRowCount: Int = 0,
    textSpanCount: Int = 0,
    textCellCount: Int = 0,
    graphicsInvalidationCount: Int = 0,
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.textRowCount = max(0, textRowCount)
    self.rangeAwareTextRowCount = max(0, rangeAwareTextRowCount)
    self.textSpanCount = max(0, textSpanCount)
    self.textCellCount = max(0, textCellCount)
    self.graphicsInvalidationCount = max(0, graphicsInvalidationCount)
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }
}

extension PresentationDamageDiagnostics {
  package init(
    damage: PresentationDamage,
    surfaceWidth: Int
  ) {
    let clampedSurfaceWidth = max(0, surfaceWidth)
    var rangeAwareTextRowCount = 0
    var textSpanCount = 0
    var textCellCount = 0

    for textRow in damage.textRows {
      if textRow.columnRanges.isEmpty {
        textSpanCount += 1
        textCellCount += clampedSurfaceWidth
        continue
      }

      rangeAwareTextRowCount += 1
      textSpanCount += textRow.columnRanges.count
      textCellCount += textRow.columnRanges.reduce(0) { partial, range in
        partial + max(0, range.upperBound - range.lowerBound)
      }
    }

    self.init(
      textRowCount: damage.textRows.count,
      rangeAwareTextRowCount: rangeAwareTextRowCount,
      textSpanCount: textSpanCount,
      textCellCount: textCellCount,
      graphicsInvalidationCount: damage.graphicsInvalidation.count,
      requiresFullTextRepaint: damage.requiresFullTextRepaint,
      requiresFullGraphicsReplay: damage.requiresFullGraphicsReplay
    )
  }
}

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
  public var presentationDamage: PresentationDamageDiagnostics?
  public var phaseTimings: FramePhaseTimings?
  public var renderGenerations: FrameRenderGenerations
  public var workerTimings: FrameWorkerTimings?
  public var mainActorTimings: FrameMainActorTimings?
  public var measurementCache: MeasurementCacheMetrics?
  public var customLayoutFallbackCount: Int
  public var firstCustomLayoutFallbackIdentity: Identity?

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
    presentationDamage: PresentationDamageDiagnostics? = nil,
    phaseTimings: FramePhaseTimings? = nil,
    renderGenerations: FrameRenderGenerations = .init(),
    workerTimings: FrameWorkerTimings? = nil,
    mainActorTimings: FrameMainActorTimings? = nil,
    measurementCache: MeasurementCacheMetrics? = nil,
    customLayoutFallbackCount: Int = 0,
    firstCustomLayoutFallbackIdentity: Identity? = nil
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
    self.presentationDamage = presentationDamage
    self.phaseTimings = phaseTimings
    self.renderGenerations = renderGenerations
    self.workerTimings = workerTimings
    self.mainActorTimings = mainActorTimings
    self.measurementCache = measurementCache
    self.customLayoutFallbackCount = customLayoutFallbackCount
    self.firstCustomLayoutFallbackIdentity = firstCustomLayoutFallbackIdentity
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

package struct PresentationDamage: Equatable, Sendable {
  package struct TextRow: Equatable, Sendable {
    package var row: Int
    package var columnRanges: [Range<Int>]

    package init(
      row: Int,
      columnRanges: [Range<Int>] = []
    ) {
      self.row = row
      self.columnRanges = PresentationDamage.normalizeColumnRanges(columnRanges)
    }
  }

  package var textRows: [TextRow]
  package var graphicsInvalidation: Set<Identity>
  package var requiresFullTextRepaint: Bool
  package var requiresFullGraphicsReplay: Bool

  package init(
    dirtyRows: Set<Int> = [],
    graphicsInvalidation: Set<Identity> = [],
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.init(
      textRows: dirtyRows.sorted().map { TextRow(row: $0) },
      graphicsInvalidation: graphicsInvalidation,
      requiresFullTextRepaint: requiresFullTextRepaint,
      requiresFullGraphicsReplay: requiresFullGraphicsReplay
    )
  }

  package init(
    textRows: [TextRow] = [],
    graphicsInvalidation: Set<Identity> = [],
    requiresFullTextRepaint: Bool = false,
    requiresFullGraphicsReplay: Bool = false
  ) {
    self.textRows = PresentationDamage.normalizeTextRows(textRows)
    self.graphicsInvalidation = graphicsInvalidation
    self.requiresFullTextRepaint = requiresFullTextRepaint
    self.requiresFullGraphicsReplay = requiresFullGraphicsReplay
  }

  package var dirtyRows: Set<Int> {
    Set(textRows.map(\.row))
  }

  package func columnRanges(for row: Int) -> [Range<Int>]? {
    textRows.first { $0.row == row }?.columnRanges
  }

  private static func normalizeTextRows(
    _ textRows: [TextRow]
  ) -> [TextRow] {
    var groupedRanges: [Int: [Range<Int>]] = [:]
    var fullRows: Set<Int> = []

    for textRow in textRows {
      if textRow.columnRanges.isEmpty {
        fullRows.insert(textRow.row)
        groupedRanges[textRow.row] = []
        continue
      }
      if fullRows.contains(textRow.row) {
        continue
      }
      groupedRanges[textRow.row, default: []].append(contentsOf: textRow.columnRanges)
    }

    return groupedRanges.keys.sorted().map { row in
      if fullRows.contains(row) {
        return TextRow(row: row)
      }
      return TextRow(row: row, columnRanges: groupedRanges[row] ?? [])
    }
  }

  private static func normalizeColumnRanges(
    _ columnRanges: [Range<Int>]
  ) -> [Range<Int>] {
    let normalized =
      columnRanges
      .map { range in
        let lowerBound = max(0, range.lowerBound)
        let upperBound = max(lowerBound, range.upperBound)
        return lowerBound..<upperBound
      }
      .filter { !$0.isEmpty }
      .sorted { lhs, rhs in
        if lhs.lowerBound == rhs.lowerBound {
          return lhs.upperBound < rhs.upperBound
        }
        return lhs.lowerBound < rhs.lowerBound
      }

    guard let first = normalized.first else {
      return []
    }

    var merged: [Range<Int>] = [first]
    for range in normalized.dropFirst() {
      let lastIndex = merged.index(before: merged.endIndex)
      let lastRange = merged[lastIndex]
      if range.lowerBound <= lastRange.upperBound {
        merged[lastIndex] = lastRange.lowerBound..<max(lastRange.upperBound, range.upperBound)
      } else {
        merged.append(range)
      }
    }
    return merged
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
  /// Identities whose ``DrawNode`` had a non-empty visible rect after
  /// all ancestor clip bounds were applied during rasterization.
  ///
  /// The runtime uses this set to gate animation tick scheduling on
  /// viewport visibility: if every identity affected by an in-flight
  /// animation falls outside this set, the animation is conceptually
  /// active but geometrically quiescent (its subtree is clipped by a
  /// ``ScrollView``, an inactive tab, etc.), and scheduling another
  /// deadline would only burn CPU.  When any non-animation invalidation
  /// wakes the scheduler — scroll, resize, tab switch, state change —
  /// the next frame re-evaluates this set and the tick loop resumes.
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
    measurementCache: MeasurementCacheMetrics? = nil
  ) -> Self {
    let customLayoutFallback = customLayoutFallbackSummary(resolved)
    return Self(
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
      firstCustomLayoutFallbackIdentity: customLayoutFallback.firstIdentity
    )
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
