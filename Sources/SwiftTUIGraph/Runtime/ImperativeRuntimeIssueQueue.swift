/// Runtime issues recorded outside any frame.
///
/// Imperative dispatch paths (element-binding write-back and peers) have no
/// resolving frame to buffer into: `ViewGraph.frameRuntimeIssues` resets at
/// `beginFrame`, so a dispatch-time record there would be wiped before the
/// frame-head merge reads it. This queue holds dispatch-time issues until the
/// next frame head drains them into that frame's issue channel. A frame that
/// is abandoned without reporting its issues (cancelled before its tail,
/// skipped on a stale baseline, elided, aborted) returns what it drained with
/// ``requeue(_:)``, so the next reported frame surfaces them.
///
/// The queue is process-global: in a multi-graph process the next frame to
/// render surfaces the pending issues, which keeps the channel warning-grade
/// rather than a per-graph contract.
@MainActor
package enum ImperativeRuntimeIssueQueue {
  package private(set) static var pending: [RuntimeIssue] = []

  package static func record(_ issue: RuntimeIssue) {
    guard !pending.contains(issue) else {
      return
    }
    pending.append(issue)
  }

  package static func drain() -> [RuntimeIssue] {
    let drained = pending
    pending = []
    return drained
  }

  /// Returns issues a frame drained but never reported to the front of the
  /// queue, ahead of the ones recorded since, each once.
  package static func requeue(_ issues: [RuntimeIssue]) {
    guard !issues.isEmpty else {
      return
    }
    var restored: [RuntimeIssue] = []
    for issue in issues where !restored.contains(issue) {
      restored.append(issue)
    }
    pending = restored + pending.filter { !restored.contains($0) }
  }
}
