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
  private var deltaCheckpointShadow: ViewGraphDeltaCheckpointShadow?
  private var currentDeltaSourceState: ViewGraph.CheckpointMutationState?
  private var dirtyEvaluationPlan: DirtyEvaluationPlan?
  private(set) package var debugLastDeltaCheckpointRestoreResult:
    ViewGraphDeltaCheckpointShadow.RestoreResult?
  private(set) package var runtimeRegistrationPublication: RuntimeRegistrationPublication =
    .unchanged
  private let publicationDiagnosticsEnabled: Bool
  private var publicationDiagnostics = RuntimeRegistrationPublicationDiagnostics()
  private var graphCheckpointDeltaRestoreCount = 0
  private var graphCheckpointFallbackRestoreCount = 0
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
    deltaCheckpointShadow = checkpoint.map { ViewGraphDeltaCheckpointShadow(baseline: $0) }
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.graphCheckpointBaselineNodeCount =
        checkpoint?.index.nodesByNodeID.count
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
    if let preparedCheckpoint,
      let checkpoint
    {
      deltaCheckpointShadow?.recordPreparedCheckpoint(
        preparedCheckpoint,
        baseline: checkpoint
      )
      currentDeltaSourceState = ViewGraph.CheckpointMutationState(
        checkpoint: preparedCheckpoint
      )
    }
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.graphCheckpointPreparedNodeCount =
        preparedCheckpoint?.index.nodesByNodeID.count
      publicationDiagnostics.graphCheckpointDirtySubtreeCandidateNodeCount =
        graphCheckpointDirtySubtreeCandidateNodeCount(in: viewGraph)
      if let deltaSummary = deltaCheckpointShadow?.summary {
        publicationDiagnostics.graphCheckpointStrategy = "full_shadow_delta"
        publicationDiagnostics.graphDeltaCheckpointNodeCount =
          deltaSummary.touchedNodeCount
        publicationDiagnostics.graphDeltaCheckpointCreatedNodeCount =
          deltaSummary.createdNodeCount
        publicationDiagnostics.graphDeltaCheckpointRemovedNodeCount =
          deltaSummary.removedNodeCount
        publicationDiagnostics.graphDeltaCheckpointEpochDelta =
          deltaSummary.graphMutationEpochDelta
      }
    }
  }

  package var debugDeltaCheckpointSummary: ViewGraphDeltaCheckpointSummary? {
    deltaCheckpointShadow?.summary
  }

  package func materializePreparedState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let preparedCheckpoint else {
      return
    }
    restoreGraphState(
      .prepared,
      targetCheckpoint: preparedCheckpoint,
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
  }

  package func restoreBaselineState(
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool = false
  ) {
    precondition(!didCommit && !didDiscard)
    guard let checkpoint else {
      return
    }
    restoreGraphState(
      .baseline,
      targetCheckpoint: checkpoint,
      in: viewGraph,
      preservingCurrentStateMutations: preservingCurrentStateMutations
    )
  }

  @discardableResult
  package func commitRuntimeRegistrations(
    from viewGraph: ViewGraph
  ) -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    var restoredNodeCount: Int?
    // On `.all` frames the publication-delta check below already builds the
    // current fingerprint; reuse it for the commit record instead of rebuilding
    // the full O(liveNodeIDs) fingerprint a second time. Other branches leave
    // this nil and the record call rebuilds.
    var committedFingerprint: RuntimeRegistrationGraphFingerprint?
    switch runtimeRegistrationPublication {
    case .unchanged:
      // Nothing was re-evaluated, so no node's registrations changed. The live
      // registry usually already holds the last committed (canonical) state.
      // Still refresh the low-volume effect registries from all live nodes:
      // one-shot/fresh caller registries may be empty even when the graph is
      // unchanged, and preference/lifecycle/task effects need matching live
      // handlers. Keep high-volume and order-sensitive registries untouched so
      // unchanged commits do not duplicate focus candidates or handlers.
      restoredNodeCount = 0
      viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
    case .all:
      let publication = viewGraph.runtimeRegistrationPublicationDeltaForCurrentFrame()
      committedFingerprint = publication?.current
      if let delta = publication?.delta,
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
        }
        viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
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
      // cannot reach capture-hosted island nodes (lazy tab bodies, portal
      // attachments, lazy viewport entries) that resolved this frame outside any
      // frontier root, and reused stable subtrees are intentionally not walked.
      // Low-volume side-effect handlers on such nodes must still reach the
      // live registries or runtime commit/observation effects cannot invoke
      // them.
      viewGraph.republishAllEffectRegistrations(into: liveRegistrations)
    }
    viewGraph.recordCommittedRuntimeRegistrationFingerprint(committedFingerprint)
    didCommit = true
    var diagnostics = liveRegistrations.diagnostics()
    if publicationDiagnosticsEnabled {
      publicationDiagnostics.publicationMode = publicationModeName
      publicationDiagnostics.subtreeRootCount = publicationSubtreeRootCount
      publicationDiagnostics.restoredNodeCount = restoredNodeCount
      publicationDiagnostics.graphCheckpointDeltaRestoreCount =
        graphCheckpointDeltaRestoreCount
      publicationDiagnostics.graphCheckpointFallbackRestoreCount =
        graphCheckpointFallbackRestoreCount
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

  private func restoreGraphState(
    _ target: ViewGraphDeltaCheckpointShadow.RestoreTarget,
    targetCheckpoint: ViewGraph.Checkpoint,
    in viewGraph: ViewGraph,
    preservingCurrentStateMutations: Bool
  ) {
    let stateMutations =
      preservingCurrentStateMutations ? viewGraph.stateMutationOverlay() : nil
    let result = restoreGraphCheckpoint(
      target,
      targetCheckpoint: targetCheckpoint,
      in: viewGraph
    )
    recordDeltaRestoreResult(result)
    if let stateMutations, !stateMutations.isEmpty {
      viewGraph.applyStateMutationOverlay(stateMutations)
    }
    if checkpoint != nil {
      currentDeltaSourceState = viewGraph.checkpointMutationStateSnapshot()
    }
  }

  private func restoreGraphCheckpoint(
    _ target: ViewGraphDeltaCheckpointShadow.RestoreTarget,
    targetCheckpoint: ViewGraph.Checkpoint,
    in viewGraph: ViewGraph
  ) -> ViewGraphDeltaCheckpointShadow.RestoreResult {
    guard let checkpoint else {
      viewGraph.restoreCheckpoint(targetCheckpoint)
      return .full(target: target, reason: .missingPreparedCheckpoint)
    }

    let plan =
      deltaCheckpointShadow?.restorePlan(
        target: target,
        in: viewGraph,
        baseline: checkpoint,
        prepared: preparedCheckpoint,
        currentSourceState: currentDeltaSourceState
      ) ?? .full(target: target, reason: .missingPreparedCheckpoint)

    switch plan {
    case .full(_, let reason):
      viewGraph.restoreCheckpoint(targetCheckpoint)
      return .full(target: target, reason: reason)
    case .delta(_, let nodeCheckpoints):
      viewGraph.restoreCheckpoint(targetCheckpoint, nodeCheckpoints: nodeCheckpoints)
      #if DEBUG
        if !deltaRestoreMatchesFullRestore(targetCheckpoint: targetCheckpoint, in: viewGraph) {
          return .full(target: target, reason: .debugOracleMismatch)
        }
      #else
        // Release: verify the scoped delta restore equals a full restore only on
        // sampled frames when the soundness probe is opted in. Off by default →
        // the delta fast path is unchanged (no extra full restore / 2x snapshot).
        if SoundnessProbeConfiguration.isSampledFrame,
          !deltaRestoreMatchesFullRestore(targetCheckpoint: targetCheckpoint, in: viewGraph)
        {
          SoundnessProbeConfiguration.recordDeltaCheckpointViolation(
            "delta restore diverged from full restore for target \(target)"
          )
          return .full(target: target, reason: .debugOracleMismatch)
        }
      #endif
      return .delta(target: target)
    }
  }

  /// Soundness oracle for the scoped delta-checkpoint restore: a delta restore
  /// must leave the graph byte-equal to a full restore. The caller has just
  /// applied the delta restore; this snapshots that state, performs a full
  /// restore, and reports whether the two snapshots matched.
  ///
  /// It is sound to mutate the graph into the full-restored state here: on a
  /// match the delta- and full-restored states are equal, and on a mismatch the
  /// caller downgrades to `.full` anyway — so the graph is always left in the
  /// state the returned result describes. Do not "optimize" the second restore
  /// away or a returned `.delta` would no longer match the graph state.
  private func deltaRestoreMatchesFullRestore(
    targetCheckpoint: ViewGraph.Checkpoint,
    in viewGraph: ViewGraph
  ) -> Bool {
    let deltaSnapshot = viewGraph.debugTotalStateSnapshot()
    viewGraph.restoreCheckpoint(targetCheckpoint)
    return deltaSnapshot == viewGraph.debugTotalStateSnapshot()
  }

  private func recordDeltaRestoreResult(
    _ result: ViewGraphDeltaCheckpointShadow.RestoreResult
  ) {
    debugLastDeltaCheckpointRestoreResult = result
    switch result {
    case .delta:
      graphCheckpointDeltaRestoreCount += 1
    case .full:
      graphCheckpointFallbackRestoreCount += 1
    }

    guard publicationDiagnosticsEnabled else {
      return
    }
    publicationDiagnostics.graphCheckpointRestoreStrategy = result.strategyName
    publicationDiagnostics.graphCheckpointRestoreFallbackReason = result.fallbackReasonName
    publicationDiagnostics.graphCheckpointDeltaRestoreCount =
      graphCheckpointDeltaRestoreCount
    publicationDiagnostics.graphCheckpointFallbackRestoreCount =
      graphCheckpointFallbackRestoreCount
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
