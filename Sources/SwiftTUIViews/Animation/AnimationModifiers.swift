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

public struct ValueAnimationModifier<Value: Equatable & Sendable>: PrimitiveViewModifier {
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

    guard valueChanged else {
      // Value unchanged — pass through the parent transaction as-is.
      return content.resolveElements(in: context)
    }

    var childContext = context
    if context.environmentValues.accessibilityReduceMotion {
      childContext.transaction.animationRequest = .disabled
    } else if let animation {
      childContext.transaction.animationRequest = .animate(animation.animationBox)
    } else {
      childContext.transaction.animationRequest = .disabled
    }
    return content.resolveElements(in: childContext)
  }

  private func previousValueAndOrdinal(
    in context: ResolveContext
  ) -> (Value?, Int?) {
    guard let viewGraph = context.viewGraph,
      let node = viewGraph.nodeForIdentity(context.identity)
    else {
      return (nil, nil)
    }
    // Use the last ordinal (high number) reserved for modifier bookkeeping
    // to avoid colliding with @State ordinals.
    let ordinal = ValueAnimationModifierSlot.reservedOrdinal
    let stored: Value = node.stateSlot(
      ordinal: ordinal,
      seed: value
    )
    return (stored, ordinal)
  }
}

enum ValueAnimationModifierSlot {
  /// Reserved modifier-only slot used to remember the previous watched
  /// value without colliding with authored `@State` storage.
  static let reservedOrdinal = StateSlotOrdinals.valueAnimation
}

// MARK: - TransactionModifier

public struct TransactionModifier: PrimitiveViewModifier {
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
    return content.resolveElements(in: childContext)
  }
}
