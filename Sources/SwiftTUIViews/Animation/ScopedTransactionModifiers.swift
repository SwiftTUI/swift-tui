public import SwiftTUICore

// MARK: - Public surface

extension View {
  /// Applies `animation` to the modifiers added inside `body` only; the
  /// iOS 17 scoped `animation(_:body:)` form.
  ///
  /// `body` receives a ``PlaceholderContentView`` standing in for this view.
  /// Modifiers it applies to the placeholder animate whenever their values
  /// change, while this view itself keeps the transaction in effect outside
  /// the modifier, so its own changes snap unless an enclosing scope
  /// animates them:
  ///
  /// ```swift
  /// Text(label)
  ///   .foregroundStyle(color)             // snaps
  ///   .animation(.easeInOut) { text in
  ///     text.offset(x: offsetX, y: 0)      // animates
  ///   }
  /// ```
  ///
  /// Passing `nil` disables animation for the modifiers in `body`.
  public func animation<Content: View>(
    _ animation: Animation?,
    @ViewBuilder body: @escaping @MainActor (PlaceholderContentView<Self>) -> Content
  ) -> some View {
    ScopedTransactionContent(
      base: self,
      transform: { $0.animation = animation },
      content: body
    )
  }

  /// Applies `transform` to the transaction seen by the modifiers added
  /// inside `body` only; the iOS 17 scoped `transaction(_:body:)` form.
  ///
  /// The wrapped view keeps the transaction in effect outside the modifier.
  /// See ``View/animation(_:body:)``.
  public func transaction<Content: View>(
    _ transform: @escaping @Sendable (inout Transaction) -> Void,
    @ViewBuilder body: @escaping @MainActor (PlaceholderContentView<Self>) -> Content
  ) -> some View {
    ScopedTransactionContent(base: self, transform: transform, content: body)
  }
}

// MARK: - ScopedTransactionContent

/// The view behind the scoped `body:` forms: resolves `content(placeholder)`
/// under the transformed transaction while the placeholder restores the
/// outer transaction for `base`, so only the modifiers applied in `content`
/// observe the transform.
package struct ScopedTransactionContent<Base: View, Content: View>: PrimitiveView, ResolvableView {
  package let base: Base
  package let transform: @Sendable (inout Transaction) -> Void
  package let content: @MainActor (PlaceholderContentView<Base>) -> Content
  private let authoringContext: AuthoringContext?

  package init(
    base: Base,
    transform: @escaping @Sendable (inout Transaction) -> Void,
    content: @escaping @MainActor (PlaceholderContentView<Base>) -> Content
  ) {
    self.base = base
    self.transform = transform
    self.content = content
    authoringContext = currentAuthoringContext()
  }

  package func resolveElements(in context: ResolveContext) -> [ResolvedNode] {
    let outer = context.transaction
    let placeholder = PlaceholderContentView(base, restoring: outer)
    let bodyContext = context.child(component: .named("body"))

    // Carry every observable Transaction field IN and write it BACK, as
    // `TransactionModifier` does (plan 2026-08-04-002 mechanics §5).
    var transaction = Transaction(
      request: outer.animationRequest,
      isContinuous: outer.isContinuous,
      customValues: outer.customValues,
      tracksVelocity: outer.tracksVelocity
    )
    transform(&transaction)

    var childContext = bodyContext
    childContext.transaction.animationRequest =
      ValueGatedTransactionSupport.registeredRequest(
        for: transaction,
        reduceMotion: context.environmentValues.renderingReduceMotion
      )
    childContext.transaction.isContinuous = transaction.isContinuous
    childContext.transaction.customValues = transaction.customValues
    childContext.transaction.tracksVelocity = transaction.tracksVelocity
    // The scoped edit must survive nested `resolveView` frame-input
    // refreshes below this node (F137); the placeholder sets the same flag
    // on its own hop when it restores `outer`.
    childContext.propagated.authoredTransactionOverride = true

    let view = withAuthoringContext(authoringContext) {
      context.trackingObservableAccess {
        content(placeholder)
      }
    }
    let bodyNode = resolveView(view, in: childContext)

    // The scope root carries the outer transaction: the controller computes
    // this node's effective transaction the ordinary way and hands it down
    // for the placeholder's `restoresOuter` hop to inherit from.
    var snapshot = outer
    snapshot.scopeRole = .scopeRoot
    return [
      ResolvedNode(
        identity: context.identity,
        kind: .view("ScopedTransaction"),
        children: [bodyNode],
        environmentSnapshot: context.environment,
        transactionSnapshot: snapshot
      )
    ]
  }
}
