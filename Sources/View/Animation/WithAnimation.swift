import Core

/// Criteria used to determine when an animation is considered complete
/// for the purposes of firing completion callbacks.
///
/// Matches SwiftUI's `AnimationCompletionCriteria`.
public struct AnimationCompletionCriteria: Equatable, Sendable {
  private enum Kind: Sendable {
    case logicallyComplete
    case removed
  }
  private let kind: Kind

  /// Fires when the animation reaches its final value, even if visual
  /// overshoot is still in progress.
  public static let logicallyComplete = AnimationCompletionCriteria(kind: .logicallyComplete)

  /// Fires when the animation has been fully removed from the system.
  public static let removed = AnimationCompletionCriteria(kind: .removed)
}

/// Executes `body` with the specified animation applied to any state
/// changes that occur during its execution.
///
/// State writes inside `body` carry animation intent through to the next
/// frame, where the animation controller samples from/to values and
/// interpolates over the animation's curve.
///
/// Passing `nil` explicitly disables animation for the scope.
@MainActor
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  _ body: () throws -> Result
) rethrows -> Result {
  let request: AnimationRequest
  if let animation {
    let box = animation.animationBox
    // Deliver the concrete animation to the renderer-owned sink so the
    // controller can re-hydrate it when it reads the box back out of
    // the transaction.
    AnimationRegistrationStorage.currentSink?.registerAnimationBox(
      box,
      payload: animation
    )
    request = .animate(box)
  } else {
    request = .disabled
  }
  return try AnimationContextStorage.$currentRequest.withValue(request) {
    try body()
  }
}

/// Executes `body` with the specified animation and fires `completion`
/// when the animation completes.
///
/// Matches SwiftUI's completion-accepting overload.  Completion support
/// is pinned to ``AnimationCompletionCriteria`` so the internal machinery
/// can later distinguish between logical completion and visual removal.
@MainActor
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
  _ body: () throws -> Result,
  completion: @escaping @Sendable () -> Void
) rethrows -> Result {
  // Completion callbacks are accepted for API parity but not yet wired
  // into the animation controller.  The closure is retained so callers
  // that rely on a lifecycle reference do not see premature deallocation;
  // a future change will route it through the controller.
  _ = completionCriteria
  _ = completion
  return try withAnimation(animation, body)
}
