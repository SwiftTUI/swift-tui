@MainActor
package final class FrameHeadRegistrationDraft {
  package let draftRegistrations: RuntimeRegistrationSet
  private var didDiscard = false

  package init() {
    draftRegistrations = .scratch()
  }

  package func draftDropEligibilityBlockers() -> Set<FrameDropEligibility.Blocker> {
    draftRegistrations.frameDropEligibilityBlockers()
  }

  package func discard() {
    precondition(!didDiscard)
    didDiscard = true
  }
}
