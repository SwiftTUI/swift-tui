import Synchronization

// Layout-pass context and its supporting value types.
//
// `LayoutPassContext` carries the mutable per-frame state the layout engine
// threads through a measure/place pass: scroll viewport context, work metrics,
// worker custom-layout cache updates, and the custom-layout compatibility
// boundary stack. `ScrollViewportContext`, `CustomLayoutCompatibilityPhase`,
// and `WorkerCustomLayoutCacheUpdate` are its companions.
//
// The read-only retained-frame query types this file was once named for now
// live in `RetainedFrameQueries.swift`.

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

  package func recordPlacedFrameFragment(
    _ fragment: PlacedFrameTableFragment
  ) {
    state.withLock {
      $0.workMetrics.placedFrameTableEntriesReused += $0.placedFrameTable.record(fragment)
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
