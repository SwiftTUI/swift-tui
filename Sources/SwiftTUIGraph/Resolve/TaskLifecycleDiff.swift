/// The single task-lifecycle diff policy: given a node's previous and current
/// task descriptors, decides which tasks cancel and which start this frame.
///
/// The policy has one churn special case, `identityChanged`: when a node's
/// resolved identity churned while its tasks persist, cancel and restart are
/// both suppressed (the task deliberately survives the relabel — cancelling on
/// every identity churn would restart long-lived tasks each frame). When the
/// identity churned and *all* tasks were removed, the cancels fire but must be
/// keyed to the *current* resolved identity (`cancelsKeyToCurrentIdentity`),
/// because the previous identity has already left the registries.
///
/// The restart suppression is scoped to nodes that *had* tasks to carry across
/// the relabel. When the node held no tasks previously (`previous.isEmpty`)
/// nothing persists, so a task that appears this frame is a genuine first
/// start and must run even though the resolved identity also churned — the
/// reduce-motion → restore transition of `PhaseAnimator` is exactly this shape
/// (the loop task is absent while reduced, then reappears under a churned
/// conditional-branch identity when motion returns).
///
/// Callers own event construction and identity/node keying; this type is the
/// shared pure policy that was previously hand-mirrored across
/// `ViewGraph.finishEvaluation`, `ViewGraph.recordReusedSubtree`, and the
/// viewport lifecycle planner.
package struct TaskLifecycleDiff: Equatable, Sendable {
  /// Tasks present previously but not currently, in previous-array order.
  package var cancels: [TaskDescriptor]
  /// Tasks present currently but not previously, in current-array order.
  package var starts: [TaskDescriptor]
  /// True when the cancels must be keyed to the current resolved identity
  /// (identity churned and every task was removed across the churn).
  package var cancelsKeyToCurrentIdentity: Bool

  package init(
    cancels: [TaskDescriptor],
    starts: [TaskDescriptor],
    cancelsKeyToCurrentIdentity: Bool
  ) {
    self.cancels = cancels
    self.starts = starts
    self.cancelsKeyToCurrentIdentity = cancelsKeyToCurrentIdentity
  }

  /// Computes the diff between `previous` and `current` task descriptors.
  ///
  /// - Parameters:
  ///   - previous: The node's task descriptors from the previous frame.
  ///   - current: The node's task descriptors this frame.
  ///   - identityChanged: Whether the node's resolved identity churned this
  ///     frame. Pass `false` for keying schemes that are identity-stable by
  ///     construction (for example the viewport arm's `ViewNodeID` keying).
  package static func between(
    previous: [TaskDescriptor],
    current: [TaskDescriptor],
    identityChanged: Bool = false
  ) -> TaskLifecycleDiff {
    let removedAllTasksAcrossIdentityChange = identityChanged && current.isEmpty
    let cancels: [TaskDescriptor] =
      if !identityChanged || removedAllTasksAcrossIdentityChange {
        previous.filter { !current.contains($0) }
      } else {
        []
      }
    let starts: [TaskDescriptor] =
      if identityChanged && !previous.isEmpty {
        []
      } else {
        current.filter { !previous.contains($0) }
      }
    return .init(
      cancels: cancels,
      starts: starts,
      cancelsKeyToCurrentIdentity: removedAllTasksAcrossIdentityChange
    )
  }
}
