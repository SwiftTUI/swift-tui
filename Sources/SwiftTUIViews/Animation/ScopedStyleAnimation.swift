import SwiftTUICore

/// Per-property authoring provenance carried through a placeholder restore.
/// A subsequent style writer outside a scoped body explicitly clears the
/// provenance, so the base view's own style remains in the outer transaction.
package struct ScopedStyleAnimationIntent: Hashable, Sendable {
  package var isScoped: Bool
  package var request: AnimationRequest
  package var batchID: AnimationBatchID?

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
