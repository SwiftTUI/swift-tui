@MainActor
package enum ViewNodeContext {
  @TaskLocal private static var taskLocalCurrent: ViewNode?
  /// Stack-lean ambient slot; see ``stackLeanResolveProfile``.
  private static var leanCurrent: ViewNode?

  package static var current: ViewNode? {
    stackLeanResolveProfile ? leanCurrent : taskLocalCurrent
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
