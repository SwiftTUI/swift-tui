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
  private(set) package var runtimeRegistrationPublication: RuntimeRegistrationPublication =
    .unchanged
  private var didCommit = false
  private var didDiscard = false

  package init(
    liveRegistrations: RuntimeRegistrationSet,
    checkpoint: ViewGraph.Checkpoint?
  ) {
    self.liveRegistrations = liveRegistrations
    self.checkpoint = checkpoint
  }

  package func recordDirtyEvaluationPlan(_ plan: DirtyEvaluationPlan?) {
    precondition(!didCommit && !didDiscard)
    if let plan {
      recordSubtreePublication(rootedAt: plan.frontierIdentities)
    } else {
      runtimeRegistrationPublication = .all
    }
  }

  package func recordPreparedCheckpoint(from viewGraph: ViewGraph) {
    precondition(!didCommit && !didDiscard)
    guard checkpoint != nil else {
      return
    }
    preparedCheckpoint = viewGraph.makeCheckpoint()
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
    switch runtimeRegistrationPublication {
    case .unchanged:
      // Nothing re-evaluated: registrations are unchanged. Re-publish the full
      // set (current behavior — leaves the live registry equal to last frame).
      viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    case .all:
      liveRegistrations.resetAll()
      viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    case .subtrees(let roots):
      // The reset is scoped to `roots`; scope the restore to match instead of
      // re-publishing the whole tree. Untouched subtrees' registrations stay in
      // place, so the result equals a full rebuild for the changed subtrees —
      // this is the O(tree) commit win (the reset already removed exactly these
      // subtrees). See the registration-restore fix plan.
      liveRegistrations.removeSubtrees(rootedAt: roots)
      viewGraph.restoreRuntimeRegistrationSubtrees(
        rootedAt: roots,
        into: liveRegistrations
      )
      // The scoped restore re-appends the changed subtree's focus registrations
      // at the end; normalize the order-sensitive focus lists back to canonical
      // identity order so the live registry is byte-identical to a full rebuild.
      liveRegistrations.normalizeScopedRestoreOrder()
    }
    didCommit = true
    return liveRegistrations.diagnostics()
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
}
