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
package protocol AnimationCompletionSink: AnyObject {
  func registerCompletion(
    batchID: AnimationBatchID,
    closure: @escaping @Sendable () -> Void
  )
}

@MainActor
package enum AnimationCompletionStorage {
  package static weak var currentSink: (any AnimationCompletionSink)?
}

/// Sink used by the View-layer `withAnimation` to deliver concrete
/// `Animation` values to the renderer's animation controller without
/// introducing a direct module dependency.
///
/// TerminalUI installs a concrete sink on the ``RunLoop`` at startup
/// via ``installAnimationRegistrationSink(_:)``.
@MainActor
package protocol AnimationRegistrationSink: AnyObject {
  func registerAnimationBox(_ box: AnimationBox, payload: any Sendable)
}

@MainActor
package enum AnimationRegistrationStorage {
  package static weak var currentSink: (any AnimationRegistrationSink)?
}

/// Sink used by the View-layer `.transition()` modifier to register
/// per-identity transitions with the renderer's animation controller.
@MainActor
package protocol TransitionRegistrationSink: AnyObject {
  func registerTransition(for identity: Identity, transition: any Sendable)
}

@MainActor
package enum TransitionRegistrationStorage {
  package static weak var currentSink: (any TransitionRegistrationSink)?
}
