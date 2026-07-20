@MainActor
package enum ViewNodeContext {
  @TaskLocal private static var taskLocalCurrent: ViewNode?
  /// Stack-lean ambient slot; see ``stackLeanResolveProfile``.
  private static var leanCurrent: ViewNode?

  package static var current: ViewNode? {
    // Lean reads fall back to the task-local so any async-scope binding
    // (always task-local — a plain slot would leak across interleaved jobs
    // at suspension points) stays visible under the lean profile. Sync
    // binds always restore on exit, so a non-nil slot is the innermost
    // scope.
    stackLeanResolveProfile ? (leanCurrent ?? taskLocalCurrent) : taskLocalCurrent
  }

  @MainActor
  package static func withValue<Result>(
    _ node: ViewNode?,
    _ apply: () -> Result
  ) -> Result {
    node?.beginRegistrationCapture()
    defer {
      node?.endRegistrationCapture()
    }
    return withCurrentValue(node, apply)
  }

  @MainActor
  package static func withCurrentValue<Result>(
    _ node: ViewNode?,
    _ apply: () -> Result
  ) -> Result {
    if stackLeanResolveProfile {
      let saved = leanCurrent
      leanCurrent = node
      defer { leanCurrent = saved }
      return apply()
    }
    return $taskLocalCurrent.withValue(node) {
      apply()
    }
  }
}
