import SwiftTUICore

// MARK: - Public surface

extension View {
  /// Associates an animation with a value-gated trigger.
  ///
  /// When `value` changes between resolves, the child subtree sees the
  /// specified animation in its transaction. Otherwise, the subtree
  /// inherits whatever animation intent the parent transaction carries.
  ///
  /// Passing `nil` explicitly suppresses any inherited animation for the
  /// subtree when `value` changes.
  public func animation<V: Equatable & Sendable>(
    _ animation: Animation?,
    value: V
  ) -> some View {
    modifier(
      ValueAnimationModifier(
        animation: animation,
        value: value
      )
    )
  }

  /// Applies a transformation to the current transaction for this
  /// subtree.
  ///
  /// Common usage is stripping animation from a specific subtree:
  /// `.transaction { $0.animationRequest = .disabled }`.
  public func transaction(
    _ transform: @escaping @Sendable (inout Transaction) -> Void
  ) -> some View {
    modifier(TransactionModifier(transform: transform))
  }
}

// MARK: - Transaction public shim

/// A mutable view of the current transaction used with ``View/transaction(_:)``.
///
/// Only the animation intent is currently available.
/// Other SwiftUI transaction fields are not part of the initial public API.
public struct Transaction: Sendable {
  /// The animation associated with the current transaction, if any.
  ///
  /// Setting this to `nil` is equivalent to `.disabled`: it suppresses
  /// inherited animation without carrying an explicit curve.
  public var animation: Animation? {
    get {
      switch request {
      case .animate(let box):
        return _animation(fromBox: box)
      case .inherit, .disabled:
        return nil
      }
    }
    set {
      if let newValue {
        request = .animate(newValue.animationBox)
      } else {
        request = .disabled
      }
    }
  }

  /// Explicitly disables animation regardless of inherited intent.
  public var disablesAnimations: Bool {
    get { request == .disabled }
    set {
      if newValue {
        request = .disabled
      } else {
        request = .inherit
      }
    }
  }

  /// Whether the transaction reports a continuous or fluid update, such
  /// as one write in a stream of during-gesture updates.
  ///
  /// The flag is author-facing metadata: transforms installed with
  /// ``View/transaction(_:)`` can read it, and scoped writes carry it to
  /// the next resolve. The framework neither sets nor consumes it yet,
  /// and the flag carries no animation intent of its own. SwiftUI does
  /// not auto-set it on gesture updates either (verified 2026-08-05).
  public var isContinuous: Bool = false

  package var request: AnimationRequest

  /// Custom ``TransactionKey`` values, keyed by key-type identity.
  /// Accessed through `transaction[MyKey.self]` (see `TransactionKey.swift`).
  package var customValues: [ObjectIdentifier: AnyHashableSendable] = [:]

  /// Completion closures added with ``addAnimationCompletion(criteria:_:)``.
  /// Consumed when the transaction opens a scope (``withTransaction(_:_:)``
  /// or a write through a ``Binding`` that stores this transaction); never
  /// carried on a resolve-time snapshot, so a completion added by a
  /// ``View/transaction(_:)`` transform has no scope to fire in and is
  /// ignored.
  package var pendingCompletions: [TransactionCompletion] = []

  /// True when this transaction carries no intent at all — applying it to
  /// a write would change nothing. `Binding` uses this to skip the
  /// `withTransaction` wrap for default-constructed stored transactions.
  package var isInert: Bool {
    request == .inherit && !isContinuous && customValues.isEmpty
      && pendingCompletions.isEmpty
  }

  /// Creates a default transaction with inherited animation intent.
  public init() {
    self.request = .inherit
  }

  /// Creates a transaction carrying `animation`; `nil` disables animation
  /// for the scope, exactly like assigning ``animation``.
  public init(animation: Animation?) {
    self.init()
    self.animation = animation
  }

  /// Adds a closure to run once the animations started under this
  /// transaction finish, at the barrier `criteria` selects.
  ///
  /// Several completions can be added to one transaction; each fires at its
  /// own barrier. The closure is main-actor isolated and can write view
  /// state directly. Completions are consumed when the transaction opens a
  /// scope: through ``withTransaction(_:_:)``, or through a write made via a
  /// ``Binding/transaction(_:)`` projection outside any enclosing
  /// `withAnimation`/`withTransaction` scope (a write inside such a scope
  /// never sees the stored transaction, so its completions do not fire).
  public mutating func addAnimationCompletion(
    criteria: AnimationCompletionCriteria = .logicallyComplete,
    _ completion: @escaping @MainActor @Sendable () -> Void
  ) {
    pendingCompletions.append(
      TransactionCompletion(barrier: criteria.barrier, closure: completion)
    )
  }

  package init(
    request: AnimationRequest,
    isContinuous: Bool = false,
    customValues: [ObjectIdentifier: AnyHashableSendable] = [:]
  ) {
    self.request = request
    self.isContinuous = isContinuous
    self.customValues = customValues
  }

  private func _animation(fromBox box: AnimationBox) -> Animation? {
    // AnimationBox retains the original Hashable value via AnyHashable,
    // so we can recover the concrete `Animation` with a typed unwrap.
    // This lets `Transaction.animation` round-trip cleanly whenever
    // the box was constructed from an `Animation` in the first place.
    box.unwrap(as: Animation.self)
  }
}

/// One completion added to a ``Transaction`` and the barrier it fires at.
package struct TransactionCompletion: Sendable {
  package var barrier: AnimationCompletionBarrier
  package var closure: @MainActor @Sendable () -> Void

  package init(
    barrier: AnimationCompletionBarrier,
    closure: @escaping @MainActor @Sendable () -> Void
  ) {
    self.barrier = barrier
    self.closure = closure
  }
}

// MARK: - ValueAnimationModifier

public struct ValueAnimationModifier<Value: Equatable & Sendable>: PrimitiveViewModifier, Sendable,
  Equatable
{
  package var animation: Animation?
  package var value: Value

  package init(
    animation: Animation?,
    value: Value
  ) {
    self.animation = animation
    self.value = value
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    // The value-gate mechanics (silent per-node slot, outer-first cursor
    // reservation, per-node ordinal claim, first-appearance baseline) are
    // shared with `ValueTransactionModifier` through
    // `ValueGatedTransactionSupport`; this modifier keeps its public shape.
    let gate = ValueGatedTransactionSupport.openGate(value: value, in: context)

    guard gate.valueChanged else {
      // Value unchanged — pass through the parent transaction as-is (the only
      // difference between `childContext` and `context` here is the cursor,
      // which is excluded from reuse-gating equality).
      let resolved = content.resolveElements(in: gate.childContext)
      gate.storeFirstAppearanceBaseline(value, in: context)
      return resolved
    }

    var childContext = gate.childContext
    // Only the request is overridden here: every other transaction field
    // (`isContinuous`, future additions) flows through on the context copy
    // untouched — this modifier authors animation intent, not a whole
    // transaction (plan 2026-08-04-002 mechanics §5).
    childContext.transaction.animationRequest =
      ValueGatedTransactionSupport.registeredRequest(
        for: animation,
        reduceMotion: context.environmentValues.renderingReduceMotion
      )
    // The narrowed request survives nested `resolveView` boundaries through
    // the authored-transaction override (F137): without it the frame-input
    // refresh re-stamped the frame-root transaction over every descendant,
    // and the request reached only the subtree roots.
    childContext.propagated.authoredTransactionOverride = true
    let resolved = content.resolveElements(in: childContext)
    gate.storeFirstAppearanceBaseline(value, in: context)
    return resolved
  }
}

// MARK: - TransactionModifier

public struct TransactionModifier: PrimitiveViewModifier, Sendable {
  package var transform: @Sendable (inout Transaction) -> Void

  package init(
    transform: @escaping @Sendable (inout Transaction) -> Void
  ) {
    self.transform = transform
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    // Every Transaction field the transform can observe must be carried
    // IN from the context snapshot here and written BACK below, or edits
    // to it silently do nothing (plan 2026-08-04-002 mechanics §5).
    var transaction = Transaction(
      request: context.transaction.animationRequest,
      isContinuous: context.transaction.isContinuous,
      customValues: context.transaction.customValues
    )
    transform(&transaction)

    var childContext = context
    if context.environmentValues.renderingReduceMotion {
      childContext.transaction.animationRequest = .disabled
    } else {
      childContext.transaction.animationRequest = transaction.request
    }
    childContext.transaction.isContinuous = transaction.isContinuous
    childContext.transaction.customValues = transaction.customValues
    // See ValueAnimationModifier: the authored edit must survive nested
    // `resolveView` frame-input refreshes below this modifier (F137).
    childContext.propagated.authoredTransactionOverride = true
    return content.resolveElements(in: childContext)
  }
}
