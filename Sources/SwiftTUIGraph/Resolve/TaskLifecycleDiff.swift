/// The single task-lifecycle diff policy: given a node's previous and current
/// task descriptors, decides which tasks cancel and which start this frame.
///
/// A resolved-identity change is a lifecycle boundary: every previous task is
/// cancelled and every current task starts, even when their descriptors compare
/// equal. Cancels use the current identity because reindexing has already removed
/// the previous identity from the graph by the time the lifecycle diff runs.
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
  /// True when cancels must be keyed to the current resolved identity because
  /// the resolved identity changed before lifecycle events were emitted.
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
    let cancels =
      identityChanged
      ? previous
      : previous.filter { !current.contains($0) }
    let starts =
      identityChanged
      ? current
      : current.filter { !previous.contains($0) }
    return .init(
      cancels: cancels,
      starts: starts,
      cancelsKeyToCurrentIdentity: identityChanged
    )
  }
}
