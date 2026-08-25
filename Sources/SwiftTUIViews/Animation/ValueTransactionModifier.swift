public import SwiftTUICore

// MARK: - Public surface

extension View {
  /// Applies a transformation to the transaction seen by this subtree
  /// whenever `value` changes; the iOS 17 `transaction(value:_:)` form.
  ///
  /// The transform runs against the transaction in effect for the resolve
  /// in which `value` changed and its result governs the subtree for that
  /// resolve, like ``View/animation(_:value:)`` with a whole transaction
  /// instead of one animation:
  ///
  /// ```swift
  /// Text("\(count)")
  ///   .foregroundStyle(count.isMultiple(of: 10) ? Color.green : .foreground)
  ///   .transaction(value: count / 10) { transaction in
  ///     transaction.animation = .easeInOut(duration: .milliseconds(600))
  ///   }
  /// ```
  public func transaction<V: Equatable & Sendable>(
    value: V,
    _ transform: @escaping @Sendable (inout Transaction) -> Void
  ) -> some View {
    modifier(ValueTransactionModifier(value: value, transform: transform))
  }
}

// MARK: - ValueTransactionModifier

/// The value-gated sibling of ``TransactionModifier``: shares the gate
/// mechanics of ``ValueAnimationModifier`` and applies a whole-transaction
/// transform when its value changes.
package struct ValueTransactionModifier<Value: Equatable & Sendable>: PrimitiveViewModifier,
  Sendable
{
  package var value: Value
  package var transform: @Sendable (inout Transaction) -> Void

  package init(value: Value, transform: @escaping @Sendable (inout Transaction) -> Void) {
    self.value = value
    self.transform = transform
  }

  package func resolve<Base: View>(
    content: ModifierContentInputs<Base>,
    in context: ResolveContext
  ) -> [ResolvedNode] {
    let gate = ValueGatedTransactionSupport.openGate(value: value, in: context)

    guard gate.valueChanged else {
      let resolved = content.resolveElements(in: gate.childContext)
      gate.storeFirstAppearanceBaseline(value, in: context)
      return resolved
    }

    // Carry every observable Transaction field IN and write it BACK, exactly
    // as `TransactionModifier` does (plan 2026-08-04-002 mechanics §5).
    var transaction = Transaction(
      request: context.transaction.animationRequest,
      isContinuous: context.transaction.isContinuous,
      customValues: context.transaction.customValues,
      tracksVelocity: context.transaction.tracksVelocity
    )
    transform(&transaction)

    var childContext = gate.childContext
    childContext.transaction.animationRequest =
      ValueGatedTransactionSupport.registeredRequest(
        for: transaction,
        reduceMotion: context.environmentValues.renderingReduceMotion
      )
    childContext.transaction.isContinuous = transaction.isContinuous
    childContext.transaction.customValues = transaction.customValues
    childContext.transaction.tracksVelocity = transaction.tracksVelocity
    childContext.propagated.authoredTransactionOverride = true
    let resolved = content.resolveElements(in: childContext)
    gate.storeFirstAppearanceBaseline(value, in: context)
    return resolved
  }
}

// MARK: - ValueGatedTransactionSupport

/// The value-gate mechanics shared by ``ValueAnimationModifier`` and
/// ``ValueTransactionModifier``: the silent per-node slot that remembers the
/// last value, the outer-first cursor reservation for stacked modifiers, the
/// per-node ordinal claim, and the first-appearance baseline store.
package enum ValueGatedTransactionSupport {
  /// One opened gate: whether the value changed since the last resolve, the
  /// child context to resolve under, and the reservation to complete once
  /// the node exists.
  package struct Gate {
    package let valueChanged: Bool
    package let childContext: ResolveContext
    package let firstAppearanceOrdinal: Int?

    /// Stores the reserved first-appearance baseline on the now-minted node.
    /// Skips a slot already holding a *different* type: the outer-first
    /// cursor keeps stacked modifiers' ordinals distinct so this cannot arise
    /// from a well-formed chain, but leaving a foreign occupant untouched
    /// keeps the slot's stored-type invariant (`AnyStateSlot.set`) trap-free
    /// regardless.
    @MainActor
    package func storeFirstAppearanceBaseline<Value: Equatable & Sendable>(
      _ value: Value,
      in context: ResolveContext
    ) {
      guard let ordinal = firstAppearanceOrdinal,
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
  }

  /// Reads the previous value from a non-invalidating state slot, stores the
  /// current one without invalidating, and reserves the first-appearance
  /// baseline when the node does not exist yet.
  @MainActor
  package static func openGate<Value: Equatable & Sendable>(
    value: Value,
    in context: ResolveContext
  ) -> Gate {
    let (previousValue, ordinal) = previousValueAndOrdinal(for: value, in: context)
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
    // Advance the cursor so a stacked inner value-gated modifier at this same
    // identity reserves the next index, matching the per-node counter's
    // outer-first claim sequence. Reset to 0 across every identity boundary
    // (the cursor is a direct `ResolveContext` field, so `child` /
    // `replacingIdentity` drop it) — one identity is one node, one counter.
    childContext.valueAnimationOrdinalCursor = context.valueAnimationOrdinalCursor + 1

    return Gate(
      valueChanged: valueChanged,
      childContext: childContext,
      firstAppearanceOrdinal: firstAppearanceOrdinal
    )
  }

  /// The request a value-gated modifier authors for `animation`: `.disabled`
  /// under reduce motion or for `nil`, otherwise `.animate` with the box
  /// registered on the renderer-owned sink (the `withAnimation` contract:
  /// the controller purges any active animation whose box carries no
  /// registration in the same render pass, so an unregistered curve dies
  /// before its first tick).
  @MainActor
  package static func registeredRequest(
    for animation: Animation?,
    reduceMotion: Bool
  ) -> AnimationRequest {
    guard !reduceMotion, let animation else {
      return .disabled
    }
    let box = animation.animationBox
    AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(box, payload: animation)
    return .animate(box)
  }

  /// The request a transformed transaction authors: its own request, with a
  /// public `Animation` re-registered on the sink so the curve survives its
  /// first tick.
  @MainActor
  package static func registeredRequest(
    for transaction: Transaction,
    reduceMotion: Bool
  ) -> AnimationRequest {
    if reduceMotion {
      return .disabled
    }
    if case .animate(let box) = transaction.request,
      let animation = box.unwrap(as: Animation.self)
    {
      AnimationRegistrationStorage.effectiveSink?.registerAnimationBox(box, payload: animation)
    }
    return transaction.request
  }

  @MainActor
  private static func previousValueAndOrdinal<Value: Equatable & Sendable>(
    for value: Value,
    in context: ResolveContext
  ) -> (Value?, Int?) {
    guard let viewGraph = context.viewGraph,
      let node = viewGraph.nodeForIdentity(context.identity)
    else {
      return (nil, nil)
    }
    // Each stacked value-gated modifier on one node claims its own
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
