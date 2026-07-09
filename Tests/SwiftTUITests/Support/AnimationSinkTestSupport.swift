@testable import SwiftTUIGraph
@testable import SwiftTUIRuntime

/// Binds the animation registration/transition/completion sinks for the
/// enclosing scope via their task-locals (F116). Replaces the deleted
/// `static weak var currentSink` test fallback: the last-bound global let
/// concurrently interleaved tests clobber each other's sinks across
/// suspension points; a task-local binding cannot leak between tests.
@MainActor
func withAnimationSinks<R>(
  _ controller: AnimationController,
  _ body: () async throws -> R
) async rethrows -> R {
  try await AnimationRegistrationStorage.withSink(controller) {
    try await TransitionRegistrationStorage.withSink(controller) {
      try await AnimationCompletionStorage.withSink(controller) {
        try await body()
      }
    }
  }
}

/// Synchronous variant for tests whose driving is entirely synchronous.
@MainActor
func withAnimationSinks<R>(
  _ controller: AnimationController,
  _ body: () throws -> R
) rethrows -> R {
  try AnimationRegistrationStorage.withSink(controller) {
    try TransitionRegistrationStorage.withSink(controller) {
      try AnimationCompletionStorage.withSink(controller) {
        try body()
      }
    }
  }
}
