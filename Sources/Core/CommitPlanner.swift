/// Produces a runtime-facing commit plan from resolved structure and semantics.
public struct CommitPlanner {
  public init() {}

  /// Plans lifecycle and handler-installation work for a frame.
  public func plan(
    resolved: ResolvedNode,
    semantics: SemanticSnapshot,
    transaction: TransactionSnapshot = .init(),
    previousLifecycleState: CommittedLifecycleState? = nil
  ) -> CommitPlan {
    let nextLifecycleState = lifecycleState(from: resolved)
    let lifecycle = lifecycleDiff(
      previous: previousLifecycleState ?? .init(),
      next: nextLifecycleState
    )
    let handlerInstallations = semantics.interactionRegions.map {
      HandlerInstallation(handlerID: $0.routeID)
    }
    return CommitPlan(
      transaction: transaction,
      semanticSnapshot: semantics,
      lifecycle: lifecycle,
      nextLifecycleState: nextLifecycleState,
      handlerInstallations: handlerInstallations
    )
  }

  private func lifecycleState(
    from resolved: ResolvedNode
  ) -> CommittedLifecycleState {
    var nodes: [CommittedLifecycleNode] = []
    resolved.collectLifecycleNodes(into: &nodes)
    return .init(nodes: nodes)
  }

  private func lifecycleDiff(
    previous: CommittedLifecycleState,
    next: CommittedLifecycleState
  ) -> [LifecycleCommitEntry] {
    let previousByIdentity = Dictionary(
      uniqueKeysWithValues: previous.nodes.map { ($0.identity, $0) }
    )
    let nextByIdentity = Dictionary(
      uniqueKeysWithValues: next.nodes.map { ($0.identity, $0) }
    )

    var entries: [LifecycleCommitEntry] = []

    for previousNode in previous.nodes.reversed() {
      guard let nextNode = nextByIdentity[previousNode.identity] else {
        if let task = previousNode.task {
          entries.append(
            .init(
              identity: previousNode.identity,
              operation: .taskCancel(task)
            )
          )
        }
        if !previousNode.disappearHandlerIDs.isEmpty {
          entries.append(
            .init(
              identity: previousNode.identity,
              operation: .disappear(handlerIDs: previousNode.disappearHandlerIDs)
            )
          )
        }
        continue
      }

      if previousNode.task != nextNode.task, let task = previousNode.task {
        entries.append(
          .init(
            identity: previousNode.identity,
            operation: .taskCancel(task)
          )
        )
      }
    }

    for nextNode in next.nodes {
      if previousByIdentity[nextNode.identity] == nil,
        !nextNode.appearHandlerIDs.isEmpty
      {
        entries.append(
          .init(
            identity: nextNode.identity,
            operation: .appear(handlerIDs: nextNode.appearHandlerIDs)
          )
        )
      }
    }

    for nextNode in next.nodes {
      let previousTask = previousByIdentity[nextNode.identity]?.task
      if previousTask != nextNode.task, let task = nextNode.task {
        entries.append(
          .init(
            identity: nextNode.identity,
            operation: .taskStart(task)
          )
        )
      }
    }

    return entries
  }
}
