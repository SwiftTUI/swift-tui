/// Produces a runtime-facing commit plan from resolved structure and semantics.
package struct CommitPlanner {
  package init() {}

  /// Plans lifecycle and handler-installation work for a frame.
  package func plan(
    resolved: ResolvedNode,
    placed: PlacedNode? = nil,
    semantics: SemanticSnapshot,
    transaction: TransactionSnapshot = .init(),
    lifecycleEvents: [LifecycleEvent] = []
  ) -> CommitPlan {
    let lifecycle = lifecycleEvents.map(lifecycleCommitEntry)
    let handlerInstallations = semantics.interactionRegions.map {
      HandlerInstallation(handlerID: $0.routeID)
    }
    return CommitPlan(
      transaction: transaction,
      semanticSnapshot: semantics,
      lifecycle: lifecycle,
      handlerInstallations: handlerInstallations
    )
  }

  private func lifecycleCommitEntry(
    from event: LifecycleEvent
  ) -> LifecycleCommitEntry {
    let operation: LifecycleCommitOperation =
      switch event.operation {
      case .appear(let handlerIDs):
        .appear(handlerIDs: handlerIDs)
      case .disappear(let handlerIDs):
        .disappear(handlerIDs: handlerIDs)
      case .change(let handlerIDs):
        .change(handlerIDs: handlerIDs)
      case .taskStart(let descriptor):
        .taskStart(descriptor)
      case .taskCancel(let descriptor):
        .taskCancel(descriptor)
      }

    return .init(
      viewNodeID: event.viewNodeID,
      identity: event.identity,
      operation: operation
    )
  }
}
