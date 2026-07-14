package import SwiftTUICore

// MARK: - Public surface

extension View {
  /// Associates an animation with a value-gated trigger.
  ///
  /// When `value` changes between resolves, the child subtree sees the
  /// specified animation in its transaction; otherwise the subtree
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
/// Only the animation intent is currently exposed; other SwiftUI
/// transaction fields are out of scope for the initial public slice.
public struct Transaction: Sendable {
  /// The animation associated with the current transaction, if any.
  ///
  /// Setting this to `nil` is equivalent to `.disabled` — it suppresses
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

  package var request: AnimationRequest

  /// Creates a default transaction with inherited animation intent.
  public init() {
    self.request = .inherit
  }

  package init(request: AnimationRequest) {
    self.request = request
  }

  private func _animation(fromBox box: AnimationBox) -> Animation? {
    // AnimationBox retains the original Hashable value via AnyHashable,
    // so we can recover the concrete `Animation` with a typed unwrap.
    // This lets `Transaction.animation` round-trip cleanly whenever
    // the box was constructed from an `Animation` in the first place.
    box.unwrap(as: Animation.self)
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
    // Read the previous value from a non-invalidating state slot.
    let (previousValue, ordinal) = previousValueAndOrdinal(in: context)
    let valueChanged = previousValue.map { $0 != value } ?? true

    // Store the current value without invalidating.
    if let ordinal, let node = context.viewGraph?.nodeForIdentity(context.identity) {
      node.setStateSlotSilently(ordinal: ordinal, value: value)
    }

    // First-appearance baseline reservation. When the identity's node does not
    // yet exist pre-resolve (a replacement `.id`, a freshly inserted entity),
    // `previousValueAndOrdinal` returns `(nil, nil)` and no baseline is stored:
    // the node mints deeper inside `content.resolveElements`, after this read.
    // The next frame then re-seeds the still-empty slot with the *current*
    // value, so a genuine change is never detected and the replacement owner
    // never animates. Reserve this modifier's slot ordinal now from the
    // identity-scoped context cursor — which advances OUTER-first, exactly
    // mirroring the per-node `claimValueAnimationModifierOrdinal` order the
    // steady-state read uses — and store the baseline post-resolve once the
    // node exists. Claiming from the node counter post-resolve instead would
    // reverse stacked modifiers' ordinals (post-resolve unwinds inner-first),
    // desyncing the next frame's read; the pre-resolve cursor cannot.
    let firstAppearanceOrdinal: Int? =
      ordinal == nil
      ? StateSlotOrdinals.valueAnimation(context.valueAnimationOrdinalCursor)
      : nil

    var childContext = context
    // Advance the cursor so a stacked inner `.animation(_, value:)` at this
    // same identity reserves the next index, matching the per-node counter's
    // outer-first claim sequence. Reset to 0 across every identity boundary
    // (the cursor is a direct `ResolveContext` field, so `child` /
    // `replacingIdentity` drop it) — one identity is one node, one counter.
    childContext.valueAnimationOrdinalCursor = context.valueAnimationOrdinalCursor + 1

    guard valueChanged else {
      // Value unchanged — pass through the parent transaction as-is (the only
      // difference between `childContext` and `context` here is the cursor,
      // which is excluded from reuse-gating equality).
      let resolved = content.resolveElements(in: childContext)
      storeFirstAppearanceBaseline(firstAppearanceOrdinal, in: context)
      return resolved
    }

    if context.environmentValues.accessibilityReduceMotion {
      childContext.transaction.animationRequest = .disabled
    } else if let animation {
      // Deliver the concrete animation to the renderer-owned sink (the
      // `withAnimation` contract): the controller purges any active
      // animation whose box carries no registration in the same render
      // pass, so an unregistered value-animation curve dies before its
      // first tick.
      let box = animation.animationBox
      AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(
        box,
        payload: animation
      )
      childContext.transaction.animationRequest = .animate(box)
    } else {
      childContext.transaction.animationRequest = .disabled
    }
    // The narrowed request survives nested `resolveView` boundaries through
    // the authored-transaction override (F137): without it the frame-input
    // refresh re-stamped the frame-root transaction over every descendant,
    // and the request reached only the subtree roots.
    childContext.propagated.authoredTransactionOverride = true
    let resolved = content.resolveElements(in: childContext)
    storeFirstAppearanceBaseline(firstAppearanceOrdinal, in: context)
    return resolved
  }

  /// Stores the reserved first-appearance baseline on the now-minted node.
  /// Skips a slot already holding a *different* type: the outer-first cursor
  /// keeps stacked modifiers' ordinals distinct so this cannot arise from a
  /// well-formed chain, but leaving a foreign occupant untouched keeps the
  /// slot's stored-type invariant (`AnyStateSlot.set`) trap-free regardless.
  private func storeFirstAppearanceBaseline(
    _ ordinal: Int?,
    in context: ResolveContext
  ) {
    guard let ordinal,
      let node = context.viewGraph?.nodeForIdentity(context.identity)
    else {
      return
    }
    if let existing = node.stateSlotStorage(ordinal: ordinal),
      existing.isInitialized,
      !existing.stores(Value.self)
    {
      return
    }
    node.setStateSlotSilently(ordinal: ordinal, value: value)
  }

  private func previousValueAndOrdinal(
    in context: ResolveContext
  ) -> (Value?, Int?) {
    guard let viewGraph = context.viewGraph,
      let node = viewGraph.nodeForIdentity(context.identity)
    else {
      return (nil, nil)
    }
    // Each stacked `.animation(_, value:)` on one node claims its own
    // per-resolve ordinal (reset with the node's other modifier-ordinal
    // counters): a shared slot would alias two stacked modifiers'
    // baselines — each write invalidates the other's comparison, so every
    // steady-state resolve manufactures a phantom "value changed" — and
    // would trap on the slot's stored-type check when the watched values
    // have different types.
    let ordinal = StateSlotOrdinals.valueAnimation(
      node.claimValueAnimationModifierOrdinal()
    )
    let stored: Value = node.stateSlot(
      ordinal: ordinal,
      seed: value
    )
    return (stored, ordinal)
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
    var transaction = Transaction(request: context.transaction.animationRequest)
    transform(&transaction)

    var childContext = context
    if context.environmentValues.accessibilityReduceMotion {
      childContext.transaction.animationRequest = .disabled
    } else {
      childContext.transaction.animationRequest = transaction.request
    }
    // See ValueAnimationModifier: the authored edit must survive nested
    // `resolveView` frame-input refreshes below this modifier (F137).
    childContext.propagated.authoredTransactionOverride = true
    return content.resolveElements(in: childContext)
  }
}
