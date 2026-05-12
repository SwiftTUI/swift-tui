@MainActor
package final class FrameHeadRegistrationDraft {
  package enum LiveMutation: Equatable {
    case none
    case resetAll
    case removeSubtrees([Identity])
  }

  private let liveRegistrations: RuntimeRegistrationSet
  package let draftRegistrations: RuntimeRegistrationSet
  private(set) package var liveMutation: LiveMutation = .none
  private var didCommit = false
  private var didDiscard = false

  package init(liveRegistrations: RuntimeRegistrationSet) {
    self.liveRegistrations = liveRegistrations
    draftRegistrations = .scratch()
  }

  package func recordResetAll() {
    precondition(!didCommit && !didDiscard)
    liveMutation = .resetAll
  }

  package func recordRemoveSubtrees(rootedAt roots: [Identity]) {
    precondition(!didCommit && !didDiscard)
    guard !roots.isEmpty else {
      return
    }
    switch liveMutation {
    case .none:
      liveMutation = .removeSubtrees(roots)
    case .removeSubtrees(let existing):
      liveMutation = .removeSubtrees(existing + roots)
    case .resetAll:
      break
    }
  }

  @discardableResult
  package func commitRestoring(
    from viewGraph: ViewGraph,
    resolved _: ResolvedNode
  ) -> RuntimeRegistrationDiagnostics {
    precondition(!didCommit && !didDiscard)
    switch liveMutation {
    case .none:
      break
    case .resetAll:
      liveRegistrations.resetAll()
    case .removeSubtrees(let roots):
      liveRegistrations.removeSubtrees(rootedAt: roots)
    }
    viewGraph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    didCommit = true
    return liveRegistrations.diagnostics()
  }

  package func draftDropEligibilityBlockers() -> Set<FrameDropEligibility.Blocker> {
    draftRegistrations.frameDropEligibilityBlockers()
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

  package func discard() {
    precondition(!didCommit && !didDiscard)
    didDiscard = true
  }
}
