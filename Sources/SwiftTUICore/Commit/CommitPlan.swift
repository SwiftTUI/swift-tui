/// Records a handler that must be installed for the committed frame.
package struct HandlerInstallation: Equatable, Sendable {
  package var handlerID: RouteID

  package init(handlerID: RouteID) {
    self.handlerID = handlerID
  }
}

/// The runtime-facing result of the commit phase.
///
/// Commit packages the already-derived semantic snapshot with lifecycle and
/// handler-installation work that the runtime must apply in order. The semantic
/// snapshot is carried for runtime consumers; lifecycle and handler entries are
/// the commit-owned side-effect plan.
package struct CommitPlan: Equatable, Sendable {
  package var transaction: TransactionSnapshot
  package var semanticSnapshot: SemanticSnapshot
  package var lifecycle: [LifecycleCommitEntry]
  package var handlerInstallations: [HandlerInstallation]

  package init(
    transaction: TransactionSnapshot = .init(),
    semanticSnapshot: SemanticSnapshot = .init(),
    lifecycle: [LifecycleCommitEntry] = [],
    handlerInstallations: [HandlerInstallation] = []
  ) {
    self.transaction = transaction
    self.semanticSnapshot = semanticSnapshot
    self.lifecycle = lifecycle
    self.handlerInstallations = handlerInstallations
  }

  package var effectCategories: Set<CommitEffectCategory> {
    var categories = Set(lifecycle.map(\.operation.commitEffectCategory))
    if !handlerInstallations.isEmpty {
      categories.insert(.handlerInstallations)
    }
    return categories
  }
}
