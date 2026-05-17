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

  @discardableResult
  package func commitRuntimeRegistrations(
    from viewGraph: ViewGraph
  ) -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    switch runtimeRegistrationPublication {
    case .unchanged:
      break
    case .all:
      liveRegistrations.resetAll()
    case .subtrees(let roots):
      liveRegistrations.removeSubtrees(rootedAt: roots)
    }
    viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
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

  package func discard(from viewGraph: ViewGraph) {
    precondition(!didCommit && !didDiscard)
    if let checkpoint {
      viewGraph.restoreCheckpoint(checkpoint)
    }
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
