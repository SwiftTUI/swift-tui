import Testing

@testable import SwiftTUICore

@MainActor
@Suite
struct Phase2CommitPlannerTests {
  @Test("new lifecycle owner emits appear and task start deltas")
  func newLifecycleOwnerEmitsAppearAndTaskStart() {
    let task = TaskDescriptor(id: "load", priority: .medium)
    let plan = planTransition(
      from: lifecycleTree(children: []),
      to: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      )
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [
        testIdentity("Root", "Leaf"),
        testIdentity("Root", "Leaf"),
      ],
      operations: [
        .appear(handlerIDs: ["appear"]),
        .taskStart(task),
      ],
      hasNodeIDs: [false, true]
    )
  }

  @Test("stable repeats do not emit duplicate lifecycle deltas")
  func stableRepeatEmitsNoLifecycleDeltas() {
    let task = TaskDescriptor(id: "load", priority: .medium)
    let tree = lifecycleTree(
      children: [
        lifecycleNode(
          testIdentity("Root", "Leaf"),
          appear: ["appear"],
          disappear: ["disappear"],
          task: task
        )
      ]
    )
    let graph = ViewGraph()
    _ = graph.applySnapshot(tree)
    let lifecycleEvents = graph.applySnapshot(tree)
    let plan = CommitPlanner().plan(
      resolved: tree,
      semantics: .init(),
      lifecycleEvents: lifecycleEvents
    )

    #expect(plan.lifecycle.isEmpty)
  }

  @Test("stable identity gaining a task emits task start without lifecycle transitions")
  func stableIdentityGainingTaskEmitsTaskStartOnly() {
    let task = TaskDescriptor(id: "load", priority: .medium)
    let plan = planTransition(
      from: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"]
          )
        ]
      ),
      to: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      )
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [testIdentity("Root", "Leaf")],
      operations: [.taskStart(task)],
      hasNodeIDs: [true]
    )
  }

  @Test("stable identity losing a task emits task cancel without lifecycle transitions")
  func stableIdentityLosingTaskEmitsTaskCancelOnly() {
    let task = TaskDescriptor(id: "load", priority: .medium)
    let plan = planTransition(
      from: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      to: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"]
          )
        ]
      )
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [testIdentity("Root", "Leaf")],
      operations: [.taskCancel(task)],
      hasNodeIDs: [true]
    )
  }

  @Test("removal cancels task before disappear")
  func removalCancelsTaskBeforeDisappear() {
    let task = TaskDescriptor(id: "load", priority: .medium)
    let plan = planTransition(
      from: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      to: lifecycleTree(children: [])
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [
        testIdentity("Root", "Leaf"),
        testIdentity("Root", "Leaf"),
      ],
      operations: [
        .taskCancel(task),
        .disappear(handlerIDs: ["disappear"]),
      ],
      hasNodeIDs: [true, false]
    )
  }

  @Test("task identity replacement cancels and restarts without lifecycle transitions")
  func taskIdentityReplacementCancelsAndRestartsWithoutLifecycleTransitions() {
    let firstTask = TaskDescriptor(id: "load-A", priority: .medium)
    let secondTask = TaskDescriptor(id: "load-B", priority: .medium)
    let plan = planTransition(
      from: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: firstTask
          )
        ]
      ),
      to: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: secondTask
          )
        ]
      )
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [
        testIdentity("Root", "Leaf"),
        testIdentity("Root", "Leaf"),
      ],
      operations: [
        .taskCancel(firstTask),
        .taskStart(secondTask),
      ],
      hasNodeIDs: [true, true]
    )
  }

  @Test("stable identity reorder does not emit lifecycle deltas")
  func stableIdentityReorderDoesNotEmitLifecycleDeltas() {
    let plan = planTransition(
      from: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "A"),
            appear: ["appear-A"],
            disappear: ["disappear-A"]
          ),
          lifecycleNode(
            testIdentity("Root", "B"),
            appear: ["appear-B"],
            disappear: ["disappear-B"]
          ),
        ]
      ),
      to: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "B"),
            appear: ["appear-B"],
            disappear: ["disappear-B"]
          ),
          lifecycleNode(
            testIdentity("Root", "A"),
            appear: ["appear-A"],
            disappear: ["disappear-A"]
          ),
        ]
      )
    )

    #expect(plan.lifecycle.isEmpty)
  }

  @Test("indexed lazy-stack lifecycle is derived from placed visible children")
  func indexedLazyStackLifecycleUsesPlacedChildren() {
    let task = TaskDescriptor(id: "row-1", priority: .medium)
    let resolved = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "LazyVStack"),
          kind: .view("LazyVStack"),
          layoutBehavior: .lazyStack(
            axis: .vertical,
            spacing: 0,
            horizontalAlignment: .leading,
            verticalAlignment: .center
          ),
          indexedChildSource: EmptyIndexedChildSource()
        )
      ]
    )
    let placed = PlacedNode(
      identity: testIdentity("Root"),
      kind: .root,
      bounds: .init(origin: .zero, size: .zero),
      children: [
        PlacedNode(
          identity: testIdentity("Root", "LazyVStack"),
          kind: .view("LazyVStack"),
          bounds: .init(origin: .zero, size: .zero),
          children: [
            PlacedNode(
              identity: testIdentity("Root", "LazyVStack", "ID[1]"),
              kind: .view("LifecycleProbe"),
              bounds: .init(origin: .zero, size: .zero),
              semanticRole: .generic,
              lifecycleMetadata: .init(
                appearHandlerIDs: ["appear"],
                disappearHandlerIDs: ["disappear"],
                tasks: [task]
              )
            )
          ],
          semanticRole: .container
        )
      ],
      semanticRole: .container
    )

    let graph = ViewGraph()
    let lifecycleEvents = graph.applySnapshot(
      resolved,
      placed: placed
    )
    let plan = CommitPlanner().plan(
      resolved: resolved,
      placed: placed,
      semantics: .init(),
      lifecycleEvents: lifecycleEvents
    )

    expectLifecycle(
      plan.lifecycle,
      identities: [
        testIdentity("Root", "LazyVStack", "ID[1]"),
        testIdentity("Root", "LazyVStack", "ID[1]"),
      ],
      operations: [
        .appear(handlerIDs: ["appear"]),
        .taskStart(task),
      ],
      hasNodeIDs: [false, false]
    )
  }

  private func expectLifecycle(
    _ lifecycle: [LifecycleCommitEntry],
    identities: [Identity],
    operations: [LifecycleCommitOperation],
    hasNodeIDs: [Bool]
  ) {
    #expect(lifecycle.map(\.identity) == identities)
    #expect(lifecycle.map(\.operation) == operations)
    #expect(lifecycle.map { $0.viewNodeID != nil } == hasNodeIDs)
  }

  private func planTransition(
    from previous: ResolvedNode,
    to next: ResolvedNode,
    placed: PlacedNode? = nil
  ) -> CommitPlan {
    let graph = ViewGraph()
    _ = graph.applySnapshot(previous)
    let lifecycleEvents = graph.applySnapshot(
      next,
      placed: placed
    )
    return CommitPlanner().plan(
      resolved: next,
      placed: placed,
      semantics: .init(),
      lifecycleEvents: lifecycleEvents
    )
  }
}

private func lifecycleTree(
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity("Root"),
    kind: .root,
    children: children
  )
}

private func lifecycleNode(
  _ identity: Identity,
  appear: [String] = [],
  disappear: [String] = [],
  task: TaskDescriptor? = nil,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  ResolvedNode(
    identity: identity,
    kind: .view("LifecycleProbe"),
    children: children,
    lifecycleMetadata: .init(
      appearHandlerIDs: appear,
      disappearHandlerIDs: disappear,
      tasks: task.map { [$0] } ?? []
    )
  )
}

private struct EmptyIndexedChildSource: IndexedChildSource {
  let count = 0
  let identityRoot = testIdentity("Root", "LazyVStack")
  let measurementSignature = "empty"

  func child(at _: Int) -> ResolvedNode {
    preconditionFailure("No indexed children should be materialized in this test.")
  }
}
