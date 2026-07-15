/// The legacy lifetime fact that first made a stored node reachable from the
/// committed root during the teardown-coherence census.
package enum LegacyLifetimeReachabilityReason: Equatable, Hashable, Sendable {
  case root
  case structuralChild(ViewNodeID)
  case committedValue(ViewNodeID)
  case hostedDetached(ViewNodeID)
  case navigationSurface(ViewNodeID)
  case parent(ViewNodeID)
  case evaluationHost(ViewNodeID)
}

/// Test-facing snapshot of the reachability algorithm that remains authoritative
/// until Proposal -003 migrates teardown consumers to `LifetimeAnchorIndex`.
package struct LegacyLifetimeReachabilitySnapshot: Equatable, Sendable {
  package var storedNodeIDs: Set<ViewNodeID>
  package var reachableNodeIDs: Set<ViewNodeID>
  package var keepReasonsByNodeID: [ViewNodeID: LegacyLifetimeReachabilityReason]
  package var staleAliasDetail: String?

  package var unreachableNodeIDs: Set<ViewNodeID> {
    storedNodeIDs.subtracting(reachableNodeIDs)
  }
}

package enum LegacyTeardownBarrierCaller: String, Equatable, Sendable {
  case preview
  case finalize
}

package enum LegacyTeardownBarrierStage: String, CaseIterable, Equatable, Sendable {
  case resolveScopeScratch
  case entityRoutedRemoval
  case absorbedShadow
  case staleDetachedHostedRoot
  case departedNavigationSurface
}

/// The three independent legacy work queues consumed by the current barrier.
package struct LegacyTeardownWorkSnapshot: Equatable, Sendable {
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
    _ other: LegacyTeardownWorkSnapshot
  ) -> LegacyTeardownWorkSnapshot {
    LegacyTeardownWorkSnapshot(
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

package struct LegacyTeardownBarrierStageTrace: Equatable, Sendable {
  package var iteration: Int
  package var stage: LegacyTeardownBarrierStage
  package var removedNodeIDs: Set<ViewNodeID>
  package var enqueuedWork: LegacyTeardownWorkSnapshot
  package var consumedWork: LegacyTeardownWorkSnapshot
  package var endingWork: LegacyTeardownWorkSnapshot
}

package struct LegacyTeardownBarrierTrace: Equatable, Sendable {
  package var caller: LegacyTeardownBarrierCaller
  package var stages: [LegacyTeardownBarrierStageTrace]
  package var endingWork: LegacyTeardownWorkSnapshot
}

package struct TeardownBarrierResult: Equatable, Sendable {
  package var didConverge: Bool
  package var iterationCount: Int
  package var iterationBound: Int
}

/// Opt-in recorder used by Stage-0 characterization tests. Normal preview and
/// finalize calls pass no recorder and retain their existing behavior.
@MainActor
package final class LegacyTeardownBarrierTraceRecorder {
  package private(set) var trace: LegacyTeardownBarrierTrace

  package init(caller: LegacyTeardownBarrierCaller) {
    trace = LegacyTeardownBarrierTrace(
      caller: caller,
      stages: [],
      endingWork: LegacyTeardownWorkSnapshot(
        resolveScopeScratchNodeIDs: [],
        entityRoutedRemovalNodeIDs: [],
        absorbedShadowNodeIDs: [],
        departedNavigationSurfaceNodeIDs: []
      )
    )
  }

  package func record(
    iteration: Int = 0,
    stage: LegacyTeardownBarrierStage,
    nodesBefore: Set<ViewNodeID>,
    nodesAfter: Set<ViewNodeID>,
    workBefore: LegacyTeardownWorkSnapshot,
    workAfter: LegacyTeardownWorkSnapshot
  ) {
    trace.stages.append(
      LegacyTeardownBarrierStageTrace(
        iteration: iteration,
        stage: stage,
        removedNodeIDs: nodesBefore.subtracting(nodesAfter),
        enqueuedWork: workAfter.subtracting(workBefore),
        consumedWork: workBefore.subtracting(workAfter),
        endingWork: workAfter
      )
    )
  }

  package func finish(endingWork: LegacyTeardownWorkSnapshot) {
    trace.endingWork = endingWork
  }
}

/// Pure inputs to the current pending-entity keep predicate. Kept separate from
/// `RuntimeRegistrationOwnerKey` and the future relation so Stage 0 can lock the
/// exact legacy tiebreak before migration.
package struct LegacyEntityHomeKeepFacts: Equatable, Sendable {
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

package func legacyEntityHomeKeepsNode(
  _ facts: LegacyEntityHomeKeepFacts
) -> Bool {
  facts.entityIsActive
    && facts.routeOwnsNode
    && (facts.occurrence > 0 || facts.resolvedIdentityIndexOwnsNode)
}

/// Test-only injection vocabulary for exercising the legacy barrier trace and
/// checkpoint rollback. Production writers continue to mutate the queues at
/// their existing call sites.
package enum LegacyTeardownDebugWorkReason: Equatable, Sendable {
  case resolveScopeScratch
  case entityRoutedRemoval
  case absorbedShadow
  case departedNavigationSurface
}
