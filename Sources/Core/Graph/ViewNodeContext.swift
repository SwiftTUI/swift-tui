@MainActor
package enum ViewNodeContext {
  @TaskLocal package static var current: ViewNode?

  @MainActor
  package static func withValue<Result>(
    _ node: ViewNode?,
    _ apply: () -> Result
  ) -> Result {
    node?.beginRegistrationCapture()
    defer {
      node?.endRegistrationCapture()
    }
    return $current.withValue(node) {
      apply()
    }
  }
}
