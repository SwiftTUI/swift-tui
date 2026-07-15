/// The durable relation fact that first made a stored node reachable from the
/// committed root during the teardown-coherence census.
package enum LifetimeReachabilityReason: Equatable, Hashable, Sendable {
  case root
  case committedValue(ViewNodeID)
  case hostedDetached(ViewNodeID)
  case navigationSurface(ViewNodeID)
  case parent(ViewNodeID)
}

/// Test-facing snapshot of the authoritative lifetime relation closure.
package struct LifetimeReachabilitySnapshot: Equatable, Sendable {
  package var storedNodeIDs: Set<ViewNodeID>
  package var reachableNodeIDs: Set<ViewNodeID>
  package var keepReasonsByNodeID: [ViewNodeID: LifetimeReachabilityReason]
  package var staleAliasDetail: String?

  package var unreachableNodeIDs: Set<ViewNodeID> {
    storedNodeIDs.subtracting(reachableNodeIDs)
  }
}

package enum TeardownBarrierCaller: String, Equatable, Sendable {
  case preview
  case finalize
}

package enum TeardownBarrierStage: String, CaseIterable, Equatable, Sendable {
  case resolveScopeScratch
  case entityRoutedRemoval
  case absorbedShadow
  case staleDetachedHostedRoot
  case departedNavigationSurface
}

/// A reason-projected snapshot of the typed teardown work queue.
package struct TeardownWorkSnapshot: Equatable, Sendable {
  package var resolveScopeScratchNodeIDs: Set<ViewNodeID>
  package var entityRoutedRemovalNodeIDs: Set<ViewNodeID>
  package var absorbedShadowNodeIDs: Set<ViewNodeID>
  package var departedNavigationSurfaceNodeIDs: Set<ViewNodeID>

  package init(
    resolveScopeScratchNodeIDs: Set<ViewNodeID> = [],
    entityRoutedRemovalNodeIDs: Set<ViewNodeID>,
    absorbedShadowNodeIDs: Set<ViewNodeID>,
    departedNavigationSurfaceNodeIDs: Set<ViewNodeID>
  ) {
    self.resolveScopeScratchNodeIDs = resolveScopeScratchNodeIDs
    self.entityRoutedRemovalNodeIDs = entityRoutedRemovalNodeIDs
    self.absorbedShadowNodeIDs = absorbedShadowNodeIDs
    self.departedNavigationSurfaceNodeIDs = departedNavigationSurfaceNodeIDs
  }

  package var totalCount: Int {
    resolveScopeScratchNodeIDs.count
      + entityRoutedRemovalNodeIDs.count
      + absorbedShadowNodeIDs.count
      + departedNavigationSurfaceNodeIDs.count
  }

  package func subtracting(
    _ other: TeardownWorkSnapshot
  ) -> TeardownWorkSnapshot {
    TeardownWorkSnapshot(
      resolveScopeScratchNodeIDs: resolveScopeScratchNodeIDs.subtracting(
        other.resolveScopeScratchNodeIDs
      ),
      entityRoutedRemovalNodeIDs: entityRoutedRemovalNodeIDs.subtracting(
        other.entityRoutedRemovalNodeIDs
      ),
      absorbedShadowNodeIDs: absorbedShadowNodeIDs.subtracting(
        other.absorbedShadowNodeIDs
      ),
      departedNavigationSurfaceNodeIDs: departedNavigationSurfaceNodeIDs.subtracting(
        other.departedNavigationSurfaceNodeIDs
      )
    )
  }
}

package struct TeardownBarrierStageTrace: Equatable, Sendable {
  package var iteration: Int
  package var stage: TeardownBarrierStage
  package var removedNodeIDs: Set<ViewNodeID>
  package var enqueuedWork: TeardownWorkSnapshot
  package var consumedWork: TeardownWorkSnapshot
  package var endingWork: TeardownWorkSnapshot
}

package struct TeardownBarrierTrace: Equatable, Sendable {
  package var caller: TeardownBarrierCaller
  package var stages: [TeardownBarrierStageTrace]
  package var endingWork: TeardownWorkSnapshot
}

package struct TeardownBarrierResult: Equatable, Sendable {
  package var didConverge: Bool
  package var iterationCount: Int
  package var iterationBound: Int
}

/// Opt-in recorder used by barrier characterization tests. Normal preview and
/// finalize calls pass no recorder and retain their existing behavior.
@MainActor
package final class TeardownBarrierTraceRecorder {
  package private(set) var trace: TeardownBarrierTrace

  package init(caller: TeardownBarrierCaller) {
    trace = TeardownBarrierTrace(
      caller: caller,
      stages: [],
      endingWork: TeardownWorkSnapshot(
        resolveScopeScratchNodeIDs: [],
        entityRoutedRemovalNodeIDs: [],
        absorbedShadowNodeIDs: [],
        departedNavigationSurfaceNodeIDs: []
      )
    )
  }

  package func record(
    iteration: Int = 0,
    stage: TeardownBarrierStage,
    nodesBefore: Set<ViewNodeID>,
    nodesAfter: Set<ViewNodeID>,
    workBefore: TeardownWorkSnapshot,
    workAfter: TeardownWorkSnapshot
  ) {
    trace.stages.append(
      TeardownBarrierStageTrace(
        iteration: iteration,
        stage: stage,
        removedNodeIDs: nodesBefore.subtracting(nodesAfter),
        enqueuedWork: workAfter.subtracting(workBefore),
        consumedWork: workBefore.subtracting(workAfter),
        endingWork: workAfter
      )
    )
  }

  package func finish(endingWork: TeardownWorkSnapshot) {
    trace.endingWork = endingWork
  }
}

/// Pure inputs to entity-home qualification when constructing relation context.
package struct EntityHomeLifetimeFacts: Equatable, Sendable {
  package var entityIsActive: Bool
  package var routeOwnsNode: Bool
  package var occurrence: Int
  package var resolvedIdentityIndexOwnsNode: Bool

  package init(
    entityIsActive: Bool,
    routeOwnsNode: Bool,
    occurrence: Int,
    resolvedIdentityIndexOwnsNode: Bool
  ) {
    self.entityIsActive = entityIsActive
    self.routeOwnsNode = routeOwnsNode
    self.occurrence = occurrence
    self.resolvedIdentityIndexOwnsNode = resolvedIdentityIndexOwnsNode
  }
}

package func entityHomeQualifiesForLifetime(
  _ facts: EntityHomeLifetimeFacts
) -> Bool {
  facts.entityIsActive
    && facts.routeOwnsNode
    && (facts.occurrence > 0 || facts.resolvedIdentityIndexOwnsNode)
}

/// Test-only injection vocabulary for exercising the barrier trace and
/// checkpoint rollback. Production writers continue to mutate the queues at
/// their existing call sites.
package enum TeardownDebugWorkReason: Equatable, Sendable {
  case resolveScopeScratch
  case entityRoutedRemoval
  case absorbedShadow
  case departedNavigationSurface
}
