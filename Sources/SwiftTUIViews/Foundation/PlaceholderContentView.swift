import SwiftTUICore

/// A stand-in for the view a closure-taking modifier was applied to.
///
/// Matches SwiftUI's `PlaceholderContentView`. The modifier forms
/// ``View/keyframeAnimator(initialValue:trigger:content:keyframes:)``,
/// ``View/phaseAnimator(_:trigger:content:animation:)``,
/// ``View/animation(_:body:)``, and ``View/transaction(_:body:)`` hand one to
/// their closure; the closure places and decorates it as it would any view.
///
/// For the scoped `body:` forms the placeholder also restores the transaction
/// that was in effect *outside* the modifier for the wrapped view, so only
/// the modifiers applied inside the closure see the scoped animation.
public struct PlaceholderContentView<Base: View>: PrimitiveView, ResolvableView {
  package let base: Base
  /// The transaction to re-install for `base`, or `nil` to resolve `base`
  /// under the ambient transaction.
  package let restoredTransaction: TransactionSnapshot?

  package init(_ base: Base, restoring restoredTransaction: TransactionSnapshot? = nil) {
    self.base = base
    self.restoredTransaction = restoredTransaction
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    guard let restoredTransaction else {
      return base.resolveElements(in: context)
    }
    // Two nodes. The outer one is the placeholder the scoped closure
    // decorates: a modifier that stamps its content node (opacity, draw
    // effects, semantics) lands here, under the scoped transaction the
    // closure's context carries. The inner one restores the outer
    // transaction for the wrapped content; its `restoresOuter` role makes
    // the controller inherit an `.inherit` request from the scope root
    // rather than from the scoped parent it sits under.
    let restoreContext = context.child(component: .named("restore"))
    var contentContext = restoreContext.child(component: .named("content"))
    contentContext.transaction = restoredTransaction
    // The restored transaction must survive nested `resolveView` frame-input
    // refreshes below this node, exactly like an authored edit (F137).
    contentContext.propagated.authoredTransactionOverride = true
    let contentNode = resolveView(base, in: contentContext)

    var restoreSnapshot = restoredTransaction
    restoreSnapshot.scopeRole = .restoresOuter
    let restoreNode = ResolvedNode(
      identity: restoreContext.identity,
      kind: .view("PlaceholderRestore"),
      children: [contentNode],
      environmentSnapshot: context.environment,
      transactionSnapshot: restoreSnapshot
    )
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("PlaceholderContent"),
        children: [restoreNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: context.transaction
      )
    ]
  }
}
