import Testing

@testable import SwiftTUICore
@testable import SwiftTUIRuntime

// Forward-progress guard on the completed-frame drop policy: a visual-only
// frame superseded by a newer render intent may be dropped, but not
// indefinitely — under a sustained invalidation cadence faster than frame
// latency (an autonomous `.task` ticking a slow-to-render tab), every
// completed frame would otherwise be superseded before its drop decision and
// the screen would never update again (the gallery Life-tab revisit freeze).
@MainActor
struct CompletedFrameProgressGuardTests {
  private let older = RenderGeneration(1)
  private let newer = RenderGeneration(2)

  private var droppableEligibility: FrameDropEligibility {
    FrameDropEligibility(blockers: [])
  }

  @Test("a superseded visual-only frame drops while the run is short")
  func supersededVisualOnlyFrameDrops() {
    let decision = CompletedFramePolicy.dropCompletedVisualOnly.decide(
      candidateGeneration: older,
      newestDesiredGeneration: newer,
      eligibility: droppableEligibility,
      consecutiveVisualOnlyDrops: CompletedFramePolicy.maxConsecutiveVisualOnlyDrops - 1
    )
    #expect(decision.action == .dropVisualOnly)
  }

  @Test("the drop run is bounded: the next frame commits for progress")
  func boundedDropRunForcesCommit() {
    let decision = CompletedFramePolicy.dropCompletedVisualOnly.decide(
      candidateGeneration: older,
      newestDesiredGeneration: newer,
      eligibility: droppableEligibility,
      consecutiveVisualOnlyDrops: CompletedFramePolicy.maxConsecutiveVisualOnlyDrops
    )
    #expect(decision.action == .commitOrdered)
    #expect(decision.reconciliation.blockReason == .progressStarvation)
  }

  @Test("a frame at the newest generation always commits ordered")
  func newestGenerationCommitsOrdered() {
    let decision = CompletedFramePolicy.dropCompletedVisualOnly.decide(
      candidateGeneration: newer,
      newestDesiredGeneration: newer,
      eligibility: droppableEligibility,
      consecutiveVisualOnlyDrops: .max
    )
    #expect(decision.action == .commitOrdered)
    #expect(decision.reconciliation.blockReason == .orderedCommitPolicy)
  }
}
