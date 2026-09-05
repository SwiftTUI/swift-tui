import SwiftTUICore
import SwiftTUIViews

/// Completed async frame before actual commit.
///
/// The candidate contains enough data to classify stale visual-only drops. It
/// must not mutate live runtime side effects unless it flows through ordered
/// commit.
struct CompletedFrameCandidate {
  var draft: FrameHeadDraft
  var tailOutput: AsyncFrameTailDraftOutput
  var resolved: ResolvedNode
  var workerTimings: FrameWorkerTimings?
  /// Value-only outgoing-tab snapshots read while the suspended committed
  /// graph is still live. Commit applies them after prepared materialization;
  /// a dropped candidate discards them without mutating the graph.
  var dormantTabArchiveRefreshes: [DormantTabArchiveCommitRefresh]
  var capturedSubviewArchiveRefreshes: [CapturedSubviewArchiveCommitRefresh]
  /// Commit preview used only for drop classification. The live graph and
  /// runtime registrations are checkpoint-restored after building it; actual
  /// side effects are applied only by `commitCompletedFrameCandidate`.
  var previewArtifacts: FrameArtifacts
  /// The lifecycle plan computed for the preview. Ordered commit hands it
  /// back to `ViewGraph.finalizeFrame` so the plan is computed once per
  /// committed frame (F61); nothing runs on the main actor between preview
  /// and commit, so the plans are identical (DEBUG-asserted in finalize).
  var previewLifecyclePlan: ViewGraphFrameLifecycleEventPlan
  var eligibility: FrameDropEligibility
  var newestDesiredGeneration: RenderGeneration
  var dropDecision: CompletedFrameDropDecision
}
