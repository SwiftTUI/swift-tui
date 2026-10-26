import SwiftTUICore

/// Per-property authoring provenance carried through a placeholder restore.
/// A subsequent style writer outside a scoped body explicitly clears the
/// provenance, so the base view's own style remains in the outer transaction.
package struct ScopedStyleAnimationIntent: Hashable, Sendable {
  package var isScoped: Bool
  package var request: AnimationRequest
  package var batchID: AnimationBatchID?

  package init(isScoped: Bool, request: AnimationRequest, batchID: AnimationBatchID?) {
    self.isScoped = isScoped
    self.request = request
    self.batchID = batchID
  }

  package func hash(into hasher: inout Hasher) {
    hasher.combine(isScoped)
    hasher.combine(batchID)
    switch request {
    case .inherit: hasher.combine(0)
    case .disabled: hasher.combine(1)
    case .animate(let box):
      hasher.combine(2)
      hasher.combine(box)
    }
  }
}

package enum ScopedStyleAnimationContextKey {}
package enum ScopedForegroundStyleAnimationKey {}
package enum ScopedTintStyleAnimationKey {}

/// The transaction a node's `clipShape` masks animate under when it differs
/// from the node's own. `clipShape` merges its mask into the clipped content's
/// node, so without it the mask would take a transaction applied inside the
/// clip, as in `content.transaction { … }.clipShape(…)` (STUI-1319). It is
/// written on a node's own snapshot, never on a resolve context, and the
/// animation controller reads it from that snapshot only, so a descendant's
/// mask never inherits it.
package enum ClipShapeAnimationScopeKey {}

extension ResolvedNode {
  /// Records `scope`, the transaction in effect where `clipShape` is applied,
  /// for this node's mask slot. Nothing is recorded when it agrees with the
  /// node's own request and batch, so an ordinary clip is unchanged. With
  /// several clips on one node the outermost `clipShape` decides, since one
  /// slot carries every clip's path.
  package mutating func recordClipShapeAnimationScope(_ scope: TransactionSnapshot) {
    let key = ObjectIdentifier(ClipShapeAnimationScopeKey.self)
    if transactionSnapshot.animationRequest == scope.animationRequest,
      transactionSnapshot.animationBatchID == scope.animationBatchID
    {
      if transactionSnapshot.customValues[key] != nil {
        transactionSnapshot.customValues[key] = nil
      }
      return
    }
    transactionSnapshot.customValues[key] = AnyHashableSendable(
      ScopedStyleAnimationIntent(
        isScoped: true, request: scope.animationRequest, batchID: scope.animationBatchID))
  }
}

@MainActor
package func recordingScopedStyleWrite<Value>(
  _ keyPath: WritableKeyPath<EnvironmentValues, Value>, in context: ResolveContext
) -> ResolveContext {
  let key: ObjectIdentifier
  if keyPath == \EnvironmentValues.foregroundStyle {
    key = ObjectIdentifier(ScopedForegroundStyleAnimationKey.self)
  } else if keyPath == \EnvironmentValues.tintStyle {
    key = ObjectIdentifier(ScopedTintStyleAnimationKey.self)
  } else {
    return context
  }
  let isScoped =
    context.transaction.customValues[ObjectIdentifier(ScopedStyleAnimationContextKey.self)]?
    .unwrap(as: Bool.self) == true
  guard isScoped || context.transaction.customValues[key] != nil else { return context }
  var result = context
  result.transaction.customValues[key] = AnyHashableSendable(
    ScopedStyleAnimationIntent(
      isScoped: isScoped, request: context.transaction.animationRequest,
      batchID: context.transaction.animationBatchID))
  result.propagated.authoredTransactionOverride = true
  return result
}
