import SwiftTUICore

// Phase support helpers for `DefaultRendererFrameHeadCoordinator`.
//
// These are small, coordinator-agnostic utilities the frame-head pipeline
// leans on: installing the animation/transition/completion task sinks for the
// duration of a draft operation, and timing an individual pipeline phase.
// They are file-internal rather than `private` so the coordinator can reach
// them across files.

/// Installs the animation, transition, and completion task sinks for the
/// duration of `operation`, so registrations made while resolving a draft
/// route to the draft's controller.
@MainActor
func withAnimationDraftSinks<Result>(
  _ animationDraft: AnimationFrameDraft,
  operation: () -> Result
) -> Result {
  let controller = animationDraft.controller
  return AnimationRegistrationStorage.$currentTaskSink.withValue(controller) {
    TransitionRegistrationStorage.$currentTaskSink.withValue(controller) {
      AnimationCompletionStorage.$currentTaskSink.withValue(controller) {
        operation()
      }
    }
  }
}

/// Runs `operation` and returns its value alongside the elapsed duration.
/// Reports `.zero` when no clock is supplied (timing disabled).
func measurePhase<Value>(
  clock: ContinuousClock?,
  _ operation: () -> Value
) -> (Value, Duration) {
  guard let clock else {
    return (operation(), .zero)
  }
  let start = clock.now
  let value = operation()
  return (value, start.duration(to: clock.now))
}
