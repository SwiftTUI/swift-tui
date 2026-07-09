/// Task-local storage for the current animation request.
///
/// `withAnimation` (View module) sets this before executing the user's
/// mutation closure.  State writes read it and forward the request through
/// the invalidation path.
@MainActor
package enum AnimationContextStorage {
  @TaskLocal package static var currentRequest: AnimationRequest = .inherit
  /// The batch ID associated with the innermost enclosing
  /// `withAnimation` scope, or `nil` at the root.  State writes thread
  /// it alongside the animation request so every animation in the same
  /// batch can be resolved to a single completion closure.
  @TaskLocal package static var currentBatchID: AnimationBatchID? = nil
}

/// Sink used by the View-layer `withAnimation` to register completion
/// closures with the animation controller.  The controller fires the
/// closure once every animation and every removal overlay tagged with
/// the batch ID has drained.
@MainActor
package protocol AnimationCompletionSink: AnyObject, Sendable {
  func registerCompletion(
    batchID: AnimationBatchID,
    closure: @escaping @Sendable () -> Void
  )
}

@MainActor
package enum AnimationCompletionStorage {
  @TaskLocal package static var currentTaskSink: (any AnimationCompletionSink)?
  package static weak var currentSink: (any AnimationCompletionSink)?

  package static var effectiveSink: (any AnimationCompletionSink)? {
    currentTaskSink ?? currentSink
  }

  package static func withSink<Result>(
    _ sink: any AnimationCompletionSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }
}

/// Sink used by the View-layer `withAnimation` to deliver concrete
/// `Animation` values to the renderer's animation controller without
/// introducing a direct module dependency.
///
/// SwiftTUI installs a concrete sink on the ``RunLoop`` using task-local
/// storage so concurrent scenes keep their animation registrations isolated.
@MainActor
package protocol AnimationRegistrationSink: AnyObject, Sendable {
  func registerAnimationBox(_ box: AnimationBox, payload: any Sendable)
}

@MainActor
package enum AnimationRegistrationStorage {
  @TaskLocal package static var currentTaskSink: (any AnimationRegistrationSink)?
  package static weak var currentSink: (any AnimationRegistrationSink)?

  package static var effectiveSink: (any AnimationRegistrationSink)? {
    currentTaskSink ?? currentSink
  }

  package static func withSink<Result>(
    _ sink: any AnimationRegistrationSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }
}

/// Sink used by the View-layer `.transition()` modifier to register
/// per-node transitions with the renderer's animation controller.
@MainActor
package protocol TransitionRegistrationSink: AnyObject, Sendable {
  func registerTransition(for identity: Identity, transition: any Sendable)
  func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    transition: any Sendable
  )
}

extension TransitionRegistrationSink {
  package func registerTransition(
    for identity: Identity,
    viewNodeID: ViewNodeID?,
    transition: any Sendable
  ) {
    registerTransition(for: identity, transition: transition)
  }
}

@MainActor
package enum TransitionRegistrationStorage {
  @TaskLocal package static var currentTaskSink: (any TransitionRegistrationSink)?
  package static weak var currentSink: (any TransitionRegistrationSink)?

  package static var effectiveSink: (any TransitionRegistrationSink)? {
    currentTaskSink ?? currentSink
  }

  package static func withSink<Result>(
    _ sink: any TransitionRegistrationSink,
    operation: () async throws -> Result
  ) async rethrows -> Result {
    try await $currentTaskSink.withValue(sink) {
      try await operation()
    }
  }
}
