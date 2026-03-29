import Testing

@testable import Core

struct LifecycleDiffFixture: Sendable {
  var previous: ResolvedNode
  var next: ResolvedNode
  var semantics: SemanticSnapshot
  var transaction: TransactionSnapshot

  init(
    previous: ResolvedNode,
    next: ResolvedNode,
    semantics: SemanticSnapshot = .init(),
    transaction: TransactionSnapshot = .init()
  ) {
    self.previous = previous
    self.next = next
    self.semantics = semantics
    self.transaction = transaction
  }

  func commitPlan(
    planner: CommitPlanner = .init()
  ) -> CommitPlan {
    let previousPlan = planner.plan(
      resolved: previous,
      semantics: semantics,
      transaction: transaction
    )
    return planner.plan(
      resolved: next,
      semantics: semantics,
      transaction: transaction,
      previousLifecycleState: previousPlan.nextLifecycleState
    )
  }
}

func parallelLifecycleTree(
  identity: Identity = testIdentity("LifecycleRoot"),
  children: [ResolvedNode] = []
) -> ResolvedNode {
  ResolvedNode(
    identity: identity,
    kind: .root,
    children: children
  )
}

func parallelLifecycleNode(
  _ identity: Identity,
  kind: NodeKind = .view("LifecycleFixture"),
  appearHandlerIDs: [String] = [],
  disappearHandlerIDs: [String] = [],
  task: TaskDescriptor? = nil,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  ResolvedNode(
    identity: identity,
    kind: kind,
    children: children,
    lifecycleMetadata: .init(
      appearHandlerIDs: appearHandlerIDs,
      disappearHandlerIDs: disappearHandlerIDs,
      task: task
    )
  )
}

func assertLifecycleDiff(
  previous: ResolvedNode,
  next: ResolvedNode,
  expectedLifecycle: [LifecycleCommitEntry],
  expectedNextLifecycleState: CommittedLifecycleState? = nil,
  semantics: SemanticSnapshot = .init(),
  transaction: TransactionSnapshot = .init(),
  planner: CommitPlanner = .init()
) {
  let plan = LifecycleDiffFixture(
    previous: previous,
    next: next,
    semantics: semantics,
    transaction: transaction
  ).commitPlan(planner: planner)

  #expect(plan.lifecycle == expectedLifecycle)

  if let expectedNextLifecycleState {
    #expect(plan.nextLifecycleState == expectedNextLifecycleState)
  }
}
