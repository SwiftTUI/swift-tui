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

  /// Fires when the animation has been fully removed from the system.
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

/// Executes `body` with `transaction`'s animation intent applied to any
/// state changes that occur during its execution — the transaction-valued
/// form of ``withAnimation(_:_:)``, matching SwiftUI's `withTransaction`.
///
/// A default (`.inherit`) transaction leaves the enclosing scope's intent
/// in place; `disablesAnimations` suppresses it; a transaction carrying an
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
/// A fresh `AnimationBatchID` is allocated for the scope; every state
/// write performed inside `body` travels through the scheduler tagged
/// with that batch ID, and the animation controller fires `completion`
/// once every animation and every removal overlay in the batch has
/// drained.
///
/// `completionCriteria` is carried on the registration so the
/// controller can distinguish `.logicallyComplete` (curve returned nil)
/// from `.removed` (removal overlay purged).  The current controller
/// treats both as "curve returned nil for every animation in the
/// batch"; callers using `.removed` on a non-removing state change
/// will fire at the same time as `.logicallyComplete`.
@MainActor
@discardableResult
public func withAnimation<Result>(
  _ animation: Animation? = .default,
  completionCriteria: AnimationCompletionCriteria = .logicallyComplete,
  _ body: () throws -> Result,
  completion: @escaping @Sendable () -> Void
) rethrows -> Result {
  _ = completionCriteria  // reserved for when logically/removed diverge
  let batchID = AnimationBatchIDAllocator.next()
  AnimationCompletionStorage.effectiveSink?.registerCompletion(
    batchID: batchID,
    closure: completion
  )
  return try AnimationContextStorage.$currentBatchID.withValue(batchID) {
    try withAnimation(animation, body)
  }
}
