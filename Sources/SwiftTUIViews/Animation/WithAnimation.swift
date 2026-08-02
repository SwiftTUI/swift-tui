import SwiftTUICore

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

  /// Fires after the system fully removes the animation.
  public static let removed = AnimationCompletionCriteria(kind: .removed)
}

/// Monotonic allocator for `AnimationBatchID` values.  Each call to
/// `withAnimation` gets a fresh ID so the animation controller can
/// associate every animation enqueued in that scope with a single
/// completion closure.
@MainActor
enum AnimationBatchIDAllocator {
  private static var counter: UInt64 = 0

  static func next() -> AnimationBatchID {
    counter &+= 1
    return AnimationBatchID(counter)
  }
}

/// Executes `body` with the specified animation applied to any state
/// changes that occur during its execution.
///
/// State writes inside `body` carry animation intent to the next frame.
/// In that frame, the animation controller samples the start and end values.
/// Then it interpolates the values over the animation curve.
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
    AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(
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

/// Executes `body` and applies the animation intent of `transaction` to its state changes.
/// This function is the transaction-valued form of ``withAnimation(_:_:)``.
/// It matches `withTransaction` in SwiftUI.
///
/// A default (`.inherit`) transaction leaves the enclosing scope's intent
/// in place. `disablesAnimations` suppresses it. A transaction that contains an
/// animation scopes that animation exactly like `withAnimation`.
@MainActor
@discardableResult
public func withTransaction<Result>(
  _ transaction: Transaction,
  _ body: () throws -> Result
) rethrows -> Result {
  switch transaction.request {
  case .inherit:
    return try body()
  case .disabled:
    return try withAnimation(nil, body)
  case .animate(let box):
    if let animation = box.unwrap(as: Animation.self) {
      // Route through withAnimation so the box is registered with the
      // renderer-owned sink — the controller re-hydrates the payload from
      // that registration.
      return try withAnimation(animation, body)
    }
    // A box that did not originate from a public `Animation` (package
    // internals) was registered at its origin; scope it directly.
    return try AnimationContextStorage.$currentRequest.withValue(transaction.request) {
      try body()
    }
  }
}

/// Executes `body` with the specified animation and fires `completion`
/// when the animation completes.
///
/// The function creates a new `AnimationBatchID` for the scope.
/// Each state write inside `body` goes through the scheduler with that batch ID.
/// The animation controller fires `completion` after all animations and removal overlays in the batch drain.
///
/// `completionCriteria` is carried on the registration so the
/// controller can distinguish `.logicallyComplete` (curve returned nil)
/// from `.removed` (removal overlay purged). The current controller treats both as
/// "curve returned nil for every animation in the
/// batch." For a state change that does not remove content, `.removed` fires with `.logicallyComplete`.
///
/// `completion` is main-actor isolated, matching every other authored
/// action closure on this surface (``Button``'s `action`, `.onAppear`,
/// toolbar and key-command handlers).  The controller only ever fires it
/// from the main actor. Thus, the isolation adds no work at the call site.
/// The closure can write view state directly.
/// Without this isolation, the closure is `nonisolated`.
/// Then each `@State` write requires a `MainActor.assumeIsolated` hop.
///
/// The closure is wrapped in its registration-time
/// ``ImperativeAuthoringContextSnapshot``, the same way toolbar and key
/// handlers are. This behavior makes the description above accurate.
/// The controller fires completions outside a resolve pass.
/// A `@State` write without a bound authoring context does not fail.
/// The setter for `State.wrappedValue` uses `box.updateSeedValue` instead.
/// This call updates the seed that a *fresh* node uses instead of the live slot.
/// Nothing invalidates and the value
/// never changes, which is indistinguishable from the write not
/// happening. The snapshot stores identity instead of the `ViewNode`.
/// If a completion fires after its owner is gone, it does not recover a location.
/// Thus, it is inert and does not restore a dead node.
@MainActor
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
  _ body: () throws -> Result,
  completion: @escaping @MainActor @Sendable () -> Void
) rethrows -> Result {
  _ = completionCriteria  // reserved for when logically/removed diverge
  let batchID = AnimationBatchIDAllocator.next()
  let scopedCompletion: @MainActor @Sendable () -> Void
  if let snapshot = currentImperativeAuthoringContextSnapshot() {
    scopedCompletion = { withImperativeAuthoringContext(snapshot) { completion() } }
  } else {
    scopedCompletion = completion
  }
  AnimationCompletionStorage.effectiveSink?.registerCompletion(
    batchID: batchID,
    closure: scopedCompletion
  )
  return try AnimationContextStorage.$currentBatchID.withValue(batchID) {
    try withAnimation(animation, body)
  }
}
