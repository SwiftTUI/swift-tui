@MainActor
/// Draft-owned graph frame state that can be committed or discarded as a unit.
///
/// ViewGraph still applies node mutations while preparing the frame. This draft
/// owns the rollback checkpoint and the committed runtime-registration
/// publication plan so the frame-head registration draft never has to reset live
/// registries as part of its own commit.
package final class ViewGraphFrameDraft {
  package enum RuntimeRegistrationPublication: Equatable {
    case unchanged
    case all
    case subtrees([Identity])
  }

  private let liveRegistrations: RuntimeRegistrationSet
  private let checkpoint: ViewGraph.Checkpoint?
  private var preparedCheckpoint: ViewGraph.Checkpoint?
  private var dirtyEvaluationPlan: DirtyEvaluationPlan?
  private(set) package var runtimeRegistrationPublication: RuntimeRegistrationPublication =
    .unchanged
  private let publicationDiagnosticsEnabled: Bool
  private var publicationDiagnostics = RuntimeRegistrationPublicationDiagnostics()
  private var didCommit = false
  private var didDiscard = false

  package init(
    liveRegistrations: RuntimeRegistrationSet,
    checkpoint: ViewGraph.Checkpoint?,
    publicationDiagnosticsEnabled: Bool =
      RuntimeRegistrationPublicationDiagnosticsConfiguration.isEnabled
  ) {
    self.liveRegistrations = liveRegistrations
    self.checkpoint = checkpoint
    self.publicationDiagnosticsEnabled = publicationDiagnosticsEnabled
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.graphCheckpointBaselineNodeCount = checkpoint?.nodesByNodeID.count
      publicationDiagnostics.nonGraphCheckpointPresent = checkpoint != nil
    }
  }

  package func recordDirtyEvaluationPlan(
    _ plan: DirtyEvaluationPlan?,
    diagnostics dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics? = nil
  ) {
    precondition(!didCommit && !didDiscard)
    dirtyEvaluationPlan = plan
    if let plan {
      recordSubtreePublication(rootedAt: plan.frontierIdentities)
    } else {
      runtimeRegistrationPublication = .all
    }
    recordDirtyPlanDiagnostics(dirtyPlanDiagnostics)
  }

  package func recordUnchangedDirtyEvaluation(
    diagnostics dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics?
  ) {
    precondition(!didCommit && !didDiscard)
    recordDirtyPlanDiagnostics(dirtyPlanDiagnostics)
  }

  package func recordPresentationPortalRootQueued(_ queued: Bool) {
    guard publicationDiagnosticsEnabled else {
      return
    }
    publicationDiagnostics.presentationPortalRootQueued = queued
  }

  package func recordPreparedCheckpoint(from viewGraph: ViewGraph) {
    precondition(!didCommit && !didDiscard)
    guard checkpoint != nil else {
      return
    }
    preparedCheckpoint = viewGraph.makeCheckpoint()
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.graphCheckpointPreparedNodeCount =
        preparedCheckpoint?.nodesByNodeID.count
      publicationDiagnostics.graphCheckpointDirtySubtreeCandidateNodeCount =
        graphCheckpointDirtySubtreeCandidateNodeCount(in: viewGraph)
    }
  }

  package func materializePreparedState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let preparedCheckpoint else {
      return
    }
    let stateMutations =
      preservingCurrentStateMutations ? viewGraph.stateMutationOverlay() : nil
    viewGraph.restoreCheckpoint(preparedCheckpoint)
    if let stateMutations {
      viewGraph.applyStateMutationOverlay(stateMutations)
    }
  }

  package func restoreBaselineState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let checkpoint else {
      return
    }
    let stateMutations =
      preservingCurrentStateMutations ? viewGraph.stateMutationOverlay() : nil
    viewGraph.restoreCheckpoint(checkpoint)
    if let stateMutations {
      viewGraph.applyStateMutationOverlay(stateMutations)
    }
  }

  @discardableResult
  package func commitRuntimeRegistrations(
    from viewGraph: ViewGraph
  ) -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    var restoredNodeCount: Int?
    switch runtimeRegistrationPublication {
    case .unchanged:
      // Nothing was re-evaluated, so no node's registrations changed. The live
      // registry already holds the last committed (canonical) state, so there is
      // nothing to do: re-publishing would be redundant O(tree) work AND would
      // append duplicates into the order-sensitive focus lists (which are not
      // reset on this path). Skipping leaves the registry byte-identical to a
      // full rebuild.
      restoredNodeCount = 0
      break
    case .all:
      if let delta = viewGraph.runtimeRegistrationPublicationDeltaForCurrentFrame(),
        !viewGraph.runtimeRegistrationDeltaRequiresFullPublication(delta)
      {
        if publicationDiagnosticsEnabled {
          restoredNodeCount = viewGraph.runtimeRegistrationSubtreeNodeCount(
            rootedAt: delta.restorationRoots
          )
        }
        if !delta.isEmpty {
          liveRegistrations.removeSubtrees(rootedAt: delta.removalRoots)
          viewGraph.restoreRuntimeRegistrationSubtrees(
            rootedAt: delta.restorationRoots,
            into: liveRegistrations
          )
          liveRegistrations.normalizeScopedRestoreOrder()
          viewGraph.republishAllTaskRegistrations(into: liveRegistrations)
        }
      } else {
        if publicationDiagnosticsEnabled {
          restoredNodeCount = viewGraph.runtimeRegistrationLiveNodeCount
        }
        liveRegistrations.resetAll()
        viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
      }
    case .subtrees(let roots):
      // The reset is scoped to `roots`; scope the restore to match instead of
      // re-publishing the whole tree. Untouched subtrees' registrations stay in
      // place, so the result equals a full rebuild for the changed subtrees —
      // this is the O(tree) commit win (the reset already removed exactly these
      // subtrees). See the registration-restore fix plan.
      if publicationDiagnosticsEnabled {
        restoredNodeCount = viewGraph.runtimeRegistrationSubtreeNodeCount(rootedAt: roots)
      }
      liveRegistrations.removeSubtrees(rootedAt: roots)
      viewGraph.restoreRuntimeRegistrationSubtrees(
        rootedAt: roots,
        into: liveRegistrations
      )
      // The scoped restore re-appends the changed subtree's focus registrations
      // at the end; normalize the order-sensitive focus lists back to canonical
      // identity order so the live registry is byte-identical to a full rebuild.
      liveRegistrations.normalizeScopedRestoreOrder()
      // The scoped restore above walks frontier-root ViewNode subtrees, which
      // cannot reach capture-hosted island nodes (deferred tab bodies, portal
      // content) that resolved this frame outside any frontier root. Autonomous
      // tasks on such nodes must still reach the live registry or they never
      // start, so republish the (infrequent) task registry from all live nodes.
      viewGraph.republishAllTaskRegistrations(into: liveRegistrations)
    }
    viewGraph.recordCommittedRuntimeRegistrationFingerprint()
    didCommit = true
    var diagnostics = liveRegistrations.diagnostics()
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.publicationMode = publicationModeName
      publicationDiagnostics.subtreeRootCount = publicationSubtreeRootCount
      publicationDiagnostics.restoredNodeCount = restoredNodeCount
      diagnostics.publication = publicationDiagnostics
    }
    return diagnostics
  }

  package func updateCommittedScrollGeometry(
    scrollRoutes: [ScrollRoute],
    scrollTargets: [ScrollTarget]
  ) {
    liveRegistrations.scrollPositionRegistry?.updateGeometry(
      scrollRoutes: scrollRoutes,
      scrollTargets: scrollTargets
    )
  }

  package func discard(
    from viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    restoreBaselineState(
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
    didDiscard = true
  }

  private func recordSubtreePublication(rootedAt roots: [Identity]) {
    guard !roots.isEmpty else {
      return
    }
    switch runtimeRegistrationPublication {
    case .unchanged:
      runtimeRegistrationPublication = .subtrees(roots)
    case .subtrees(let existing):
      runtimeRegistrationPublication = .subtrees(existing + roots)
    case .all:
      break
    }
  }

  private func graphCheckpointDirtySubtreeCandidateNodeCount(
    in viewGraph: ViewGraph
  ) -> Int? {
    switch runtimeRegistrationPublication {
    case .unchanged:
      return 0
    case .subtrees:
      guard let dirtyEvaluationPlan else {
        return nil
      }
      return viewGraph.runtimeRegistrationSubtreeNodeCount(
        rootedAt: dirtyEvaluationPlan.frontierIdentities
      )
    case .all:
      return nil
    }
  }

  private func recordDirtyPlanDiagnostics(
    _ dirtyPlanDiagnostics: DirtyEvaluationPlanDiagnostics?
  ) {
    guard publicationDiagnosticsEnabled,
      let dirtyPlanDiagnostics
    else {
      return
    }
    publicationDiagnostics.dirtyPlanResult = dirtyPlanDiagnostics.result
    publicationDiagnostics.invalidatedIdentityCount =
      dirtyPlanDiagnostics.invalidatedIdentityCount
    publicationDiagnostics.unmappedInvalidatedIdentityCount =
      dirtyPlanDiagnostics.unmappedInvalidatedIdentityCount
    publicationDiagnostics.unmappedInvalidatedIdentitySample =
      dirtyPlanDiagnostics.unmappedInvalidatedIdentitySample
    publicationDiagnostics.selectiveEvaluationDisabledReasons =
      dirtyPlanDiagnostics.selectiveEvaluationDisabledReasons
  }

  private var publicationModeName: String {
    switch runtimeRegistrationPublication {
    case .unchanged:
      "unchanged"
    case .all:
      "all"
    case .subtrees:
      "subtrees"
    }
  }

  private var publicationSubtreeRootCount: Int {
    switch runtimeRegistrationPublication {
    case .unchanged, .all:
      0
    case .subtrees(let roots):
      roots.count
    }
  }
}
