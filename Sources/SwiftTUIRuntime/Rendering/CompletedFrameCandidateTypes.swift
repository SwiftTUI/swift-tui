import SwiftTUICore

// Support types for completed-frame candidate resolution.
//
// `DefaultRenderer+CompletedFrameCandidates.swift` previews, commits, or drops
// a completed async frame; these value types are its inputs and outputs.

/// The outcome of resolving a completed-frame candidate: either committed with
/// its artifacts, or dropped with the runtime issues observed while rendering.
enum CompletedFrameCandidateResolution {
  case committed(FrameArtifacts, CompletedFrameDropDecision)
  case dropped(runtimeIssues: [RuntimeIssue], dropDecision: CompletedFrameDropDecision)
}

/// Side effects produced by committing a frame's effects.
struct CommittedFrameEffects {
  var commitPlan: CommitPlan
  var commitDuration: Duration
  var runtimeRegistrationDiagnostics: RuntimeRegistrationDiagnostics
}

/// Pairs a candidate's previewed commit plan with the plan actually committed,
/// so tests can assert the preview matched the commit.
package struct CompletedFrameCandidateCommitPlanComparison {
  package var previewCommit: CommitPlan
  package var committedCommit: CommitPlan
  package var committedArtifacts: FrameArtifacts
}
