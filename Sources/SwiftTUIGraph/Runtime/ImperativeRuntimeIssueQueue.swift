/// Runtime issues recorded outside any frame.
///
/// Imperative dispatch paths (element-binding write-back and peers) have no
/// resolving frame to buffer into: `ViewGraph.frameRuntimeIssues` resets at
/// `beginFrame`, so a dispatch-time record there would be wiped before the
/// frame-head merge reads it. This queue holds dispatch-time issues until the
/// next frame head drains them into that frame's issue channel.
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
}
