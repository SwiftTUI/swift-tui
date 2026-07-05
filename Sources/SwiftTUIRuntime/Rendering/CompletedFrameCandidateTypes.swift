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
  /// A sibling frame committed after this head's baseline was captured, so
  /// neither committing (materializing a stale prepared checkpoint) nor
  /// dropping (restoring a stale baseline) is sound: both would rewind the
  /// sibling's committed effects. The head is discarded without touching live
  /// state and the frame intent is replayed against the post-commit graph.
  case skippedStaleBaseline(runtimeIssues: [RuntimeIssue])
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
