import Synchronization

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

/// Identity index of the previous committed frame's canonical pipeline products.
///
/// When this index is produced by frame-tail retained state, `placedByIdentity`
/// is expected to come from the baseline placed tree stored before animation
/// overlays were injected. That keeps retained placement keyed to canonical
/// layout, while overlays are re-applied from animation state each frame.
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
    var layoutDependentRealizations: [LayoutDependentContentRealization]
    var placedFrameTable: PlacedFrameTable
    var customLayoutCompatibilityDepth: Int
    var customLayoutCompatibilityDepthLimit: Int
    var runtimeIssues: [RuntimeIssue]
  }

  package static let defaultCustomLayoutCompatibilityDepthLimit = 4

  package let retainedLayout: RetainedLayoutSession?
  package let invalidatedIdentities: Set<Identity>
  private let state: Mutex<MutableState>

  package init(
    retainedLayout: RetainedLayoutSession? = nil,
    invalidatedIdentities: Set<Identity> = [],
    scrollViewportContext: ScrollViewportContext? = nil,
    customLayoutCompatibilityDepthLimit: Int = defaultCustomLayoutCompatibilityDepthLimit
  ) {
    self.retainedLayout = retainedLayout
    self.invalidatedIdentities = invalidatedIdentities
    let geometryDiagnosticsRecorder = GeometryResolutionDiagnosticsRecorder()
    state = .init(
      .init(
        scrollViewportContext: scrollViewportContext,
        workMetrics: .init(),
        workerCustomLayoutCacheUpdates: [],
        layoutDependentRealizations: [],
        placedFrameTable: .init(diagnosticsRecorder: geometryDiagnosticsRecorder),
        customLayoutCompatibilityDepth: 0,
        customLayoutCompatibilityDepthLimit: customLayoutCompatibilityDepthLimit,
        runtimeIssues: []
      )
    )
  }

  package var scrollViewportContext: ScrollViewportContext? {
    state.withLock { $0.scrollViewportContext }
  }

  package var workMetrics: LayoutWorkMetrics {
    state.withLock {
      var metrics = $0.workMetrics
      metrics.geometryResolutionDiagnostics = $0.placedFrameTable.geometryResolutionDiagnostics
      return metrics
    }
  }

  package var workerCustomLayoutCacheUpdates: [WorkerCustomLayoutCacheUpdate] {
    state.withLock { $0.workerCustomLayoutCacheUpdates }
  }

  package var runtimeIssues: [RuntimeIssue] {
    state.withLock { $0.runtimeIssues }
  }

  package var layoutDependentRealizationsByIdentity: [Identity: [ResolvedNode]] {
    state.withLock { state in
      state.layoutDependentRealizations.reduce(into: [:]) { result, realization in
        result[realization.signature.boundaryIdentity] = realization.children
      }
    }
  }

  package var placedFrameTable: PlacedFrameTable {
    state.withLock { $0.placedFrameTable }
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

  package func recordPlacedFrame(
    identity: Identity,
    bounds: CellRect,
    namedCoordinateSpaceName: String?
  ) {
    state.withLock {
      $0.placedFrameTable.record(
        identity: identity,
        bounds: bounds,
        namedCoordinateSpaceName: namedCoordinateSpaceName
      )
    }
  }

  package func recordPlacedFrames(
    in node: PlacedNode
  ) {
    state.withLock {
      var work = [node]
      while let current = work.popLast() {
        $0.placedFrameTable.record(
          identity: current.identity,
          bounds: current.bounds,
          namedCoordinateSpaceName: current.semanticMetadata.namedCoordinateSpaceName
        )
        work.append(contentsOf: current.children.reversed())
      }
    }
  }

  package func enterCustomLayoutCompatibilityBoundary(
    identity: Identity,
    debugName: String,
    phase: CustomLayoutCompatibilityPhase
  ) -> Bool {
    state.withLock { state in
      guard state.customLayoutCompatibilityDepth < state.customLayoutCompatibilityDepthLimit else {
        let issue = RuntimeIssue(
          severity: .error,
          code: "layout.customLayoutDepthLimitExceeded",
          message:
            "Custom layout \(phase.rawValue) exceeded the compatibility depth limit of "
            + "\(state.customLayoutCompatibilityDepthLimit).",
          identity: identity,
          source: debugName
        )
        if !state.runtimeIssues.contains(issue) {
          state.runtimeIssues.append(issue)
        }
        return false
      }

      state.customLayoutCompatibilityDepth += 1
      return true
    }
  }

  package func exitCustomLayoutCompatibilityBoundary() {
    state.withLock { state in
      precondition(
        state.customLayoutCompatibilityDepth > 0,
        "custom layout compatibility depth underflow"
      )
      state.customLayoutCompatibilityDepth -= 1
    }
  }

  package func realizeLayoutDependentContent(
    in context: LayoutRealizationContext,
    using realize: () -> [ResolvedNode]
  ) -> [ResolvedNode] {
    let signature = LayoutDependentContentSignature(context)
    if let cached = state.withLock({
      $0.layoutDependentRealizations.first(where: { $0.signature == signature })
    }) {
      updateWorkMetrics {
        $0.layoutDependentRealizationCacheHits += 1
      }
      return cached.children
    }

    let children = realize()
    state.withLock { state in
      state.layoutDependentRealizations.append(
        .init(
          signature: signature,
          children: children
        )
      )
      state.workMetrics.layoutDependentRealizations += 1
    }
    return children
  }
}

package enum CustomLayoutCompatibilityPhase: String, Sendable {
  case measurement
  case placement
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
