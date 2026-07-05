import SwiftTUICore

package struct SkippedFrameReconciliation: Equatable, Sendable {
  package enum Mode: String, Equatable, Sendable {
    case emptyVisualOnly = "empty_visual_only"
    case appliedSideEffects = "applied_side_effects"
    case blocked
  }

  package enum BlockReason: String, Equatable, Sendable {
    case orderedCommitPolicy = "ordered_commit_policy"
    case dropEligibilityBlockers = "drop_eligibility_blockers"
    case nonEmptyReconciliationUnavailable = "non_empty_reconciliation_unavailable"
    case progressStarvation = "progress_starvation"
  }

  package var mode: Mode
  package var blockers: Set<FrameDropEligibility.Blocker>
  package var blockReason: BlockReason?
  package var effectSummary: String

  package init(
    mode: Mode,
    blockers: Set<FrameDropEligibility.Blocker> = [],
    blockReason: BlockReason? = nil,
    effectSummary: String = "-"
  ) {
    self.mode = mode
    self.blockers = blockers
    self.blockReason = blockReason
    self.effectSummary = effectSummary
  }

  package static let emptyVisualOnly = Self(mode: .emptyVisualOnly)

  package static func appliedSideEffects(
    effectSummary: String
  ) -> Self {
    Self(
      mode: .appliedSideEffects,
      blockReason: .nonEmptyReconciliationUnavailable,
      effectSummary: effectSummary
    )
  }

  package static func blocked(
    reason: BlockReason,
    blockers: Set<FrameDropEligibility.Blocker> = []
  ) -> Self {
    Self(
      mode: .blocked,
      blockers: blockers,
      blockReason: reason
    )
  }

  package var isEmptyVisualOnly: Bool {
    mode == .emptyVisualOnly
      && blockers.isEmpty
      && blockReason == nil
      && effectSummary == "-"
  }

  package var isAvailableToRuntimePolicy: Bool {
    isEmptyVisualOnly
  }
}

package struct CompletedFrameDropDecision: Equatable, Sendable {
  package enum Action: String, Equatable, Sendable {
    case commitOrdered = "commit_ordered"
    case dropVisualOnly = "drop_visual_only"
    case blocked
  }

  package var action: Action
  package var eligibility: FrameDropEligibility.Decision
  package var reconciliation: SkippedFrameReconciliation

  package init(
    action: Action,
    eligibility: FrameDropEligibility.Decision,
    reconciliation: SkippedFrameReconciliation
  ) {
    self.action = action
    self.eligibility = eligibility
    self.reconciliation = reconciliation
  }

  package static func orderedCommit(
    eligibility: FrameDropEligibility
  ) -> Self {
    Self(
      action: .commitOrdered,
      eligibility: eligibility.decision,
      reconciliation: .blocked(
        reason: .orderedCommitPolicy,
        blockers: eligibility.blockers
      )
    )
  }

  /// Forward-progress guard: the previous completed frames were all dropped
  /// visual-only, so this one must commit even though a newer render intent is
  /// pending. Without the guard, a sustained invalidation cadence faster than
  /// the frame latency (an autonomous `.task` ticking a slow-to-render tab)
  /// supersedes every completed frame before its drop decision — each is
  /// "safely" dropped in favor of the next, and the screen never updates
  /// again (the gallery Life-tab freeze).
  package static func progressStarvationCommit(
    eligibility: FrameDropEligibility
  ) -> Self {
    Self(
      action: .commitOrdered,
      eligibility: eligibility.decision,
      reconciliation: .blocked(
        reason: .progressStarvation,
        blockers: eligibility.blockers
      )
    )
  }

  package static func blocked(
    eligibility: FrameDropEligibility
  ) -> Self {
    Self(
      action: .blocked,
      eligibility: eligibility.decision,
      reconciliation: .blocked(
        reason: .dropEligibilityBlockers,
        blockers: eligibility.blockers
      )
    )
  }

  package static func dropVisualOnly(
    eligibility: FrameDropEligibility
  ) -> Self {
    guard eligibility.decision == .canDropVisualOnly else {
      return blocked(eligibility: eligibility)
    }

    return Self(
      action: .dropVisualOnly,
      eligibility: eligibility.decision,
      reconciliation: .emptyVisualOnly
    )
  }

  package var canSkipCompletedFrame: Bool {
    action == .dropVisualOnly && reconciliation.isAvailableToRuntimePolicy
  }
}

package struct CompletedFramePolicy: Equatable, Sendable {
  package enum Mode: Equatable, Sendable {
    case orderedCommitOnly
    case dropCompletedVisualOnly
  }

  package var mode: Mode

  package init(mode: Mode = .orderedCommitOnly) {
    self.mode = mode
  }

  package static let orderedCommitOnly = Self()
  package static let dropCompletedVisualOnly = Self(mode: .dropCompletedVisualOnly)

  /// The maximum run of consecutive visual-only drops before the guard forces
  /// a commit. Dropping is an optimization for bursts (a superseded frame's
  /// content reappears in the newer frame about to render); two in a row is
  /// already a sign the pipeline is being outpaced, and the bound converts a
  /// potential presentation livelock into at-worst one committed frame per
  /// three completed ones.
  package static let maxConsecutiveVisualOnlyDrops = 2

  package func decide(
    candidateGeneration: RenderGeneration,
    newestDesiredGeneration: RenderGeneration,
    eligibility: FrameDropEligibility,
    consecutiveVisualOnlyDrops: Int = 0
  ) -> CompletedFrameDropDecision {
    guard candidateGeneration < newestDesiredGeneration else {
      return .orderedCommit(eligibility: eligibility)
    }

    switch mode {
    case .orderedCommitOnly:
      return .orderedCommit(eligibility: eligibility)
    case .dropCompletedVisualOnly:
      // Forward-progress guard: under a sustained invalidation cadence faster
      // than frame latency, every completed frame has a newer intent pending
      // and would drop forever — the screen never updates again. Bound the
      // consecutive-drop run so presentation always makes progress.
      guard consecutiveVisualOnlyDrops < Self.maxConsecutiveVisualOnlyDrops else {
        return .progressStarvationCommit(eligibility: eligibility)
      }
      return CompletedFrameDropDecision.dropVisualOnly(eligibility: eligibility)
    }
  }
}
