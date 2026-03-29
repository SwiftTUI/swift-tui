import Testing

@testable import Core

@Suite
struct Phase2CommitPlannerTests {
  @Test("new lifecycle owner emits appear and task start deltas")
  func newLifecycleOwnerEmitsAppearAndTaskStart() {
    let planner = CommitPlanner()
    let task = TaskDescriptor(id: "load", priority: .medium)

    let plan = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      semantics: .init()
    )

    #expect(
      plan.lifecycle == [
        .init(identity: testIdentity("Root", "Leaf"), operation: .appear(handlerIDs: ["appear"])),
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskStart(task)),
      ])
    #expect(
      plan.nextLifecycleState.nodes == [
        .init(
          identity: testIdentity("Root", "Leaf"),
          appearHandlerIDs: ["appear"],
          disappearHandlerIDs: ["disappear"],
          task: task
        )
      ])
  }

  @Test("stable repeats do not emit duplicate lifecycle deltas")
  func stableRepeatEmitsNoLifecycleDeltas() {
    let planner = CommitPlanner()
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

    let first = planner.plan(resolved: tree, semantics: .init())
    let second = planner.plan(
      resolved: tree,
      semantics: .init(),
      previousLifecycleState: first.nextLifecycleState
    )

    #expect(second.lifecycle.isEmpty)
    #expect(second.nextLifecycleState == first.nextLifecycleState)
  }

  @Test("stable identity gaining a task emits task start without lifecycle transitions")
  func stableIdentityGainingTaskEmitsTaskStartOnly() {
    let planner = CommitPlanner()
    let task = TaskDescriptor(id: "load", priority: .medium)

    let previous = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"]
          )
        ]
      ),
      semantics: .init()
    )

    let next = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      semantics: .init(),
      previousLifecycleState: previous.nextLifecycleState
    )

    #expect(
      next.lifecycle == [
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskStart(task))
      ])
  }

  @Test("stable identity losing a task emits task cancel without lifecycle transitions")
  func stableIdentityLosingTaskEmitsTaskCancelOnly() {
    let planner = CommitPlanner()
    let task = TaskDescriptor(id: "load", priority: .medium)

    let previous = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      semantics: .init()
    )

    let next = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"]
          )
        ]
      ),
      semantics: .init(),
      previousLifecycleState: previous.nextLifecycleState
    )

    #expect(
      next.lifecycle == [
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskCancel(task))
      ])
  }

  @Test("removal cancels task before disappear")
  func removalCancelsTaskBeforeDisappear() {
    let planner = CommitPlanner()
    let task = TaskDescriptor(id: "load", priority: .medium)
    let previous = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: task
          )
        ]
      ),
      semantics: .init()
    )

    let next = planner.plan(
      resolved: lifecycleTree(children: []),
      semantics: .init(),
      previousLifecycleState: previous.nextLifecycleState
    )

    #expect(
      next.lifecycle == [
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskCancel(task)),
        .init(
          identity: testIdentity("Root", "Leaf"), operation: .disappear(handlerIDs: ["disappear"])),
      ])
    #expect(next.nextLifecycleState.nodes.isEmpty)
  }

  @Test("task identity replacement cancels and restarts without lifecycle transitions")
  func taskIdentityReplacementCancelsAndRestartsWithoutLifecycleTransitions() {
    let planner = CommitPlanner()
    let firstTask = TaskDescriptor(id: "load-A", priority: .medium)
    let secondTask = TaskDescriptor(id: "load-B", priority: .medium)

    let previous = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: firstTask
          )
        ]
      ),
      semantics: .init()
    )

    let next = planner.plan(
      resolved: lifecycleTree(
        children: [
          lifecycleNode(
            testIdentity("Root", "Leaf"),
            appear: ["appear"],
            disappear: ["disappear"],
            task: secondTask
          )
        ]
      ),
      semantics: .init(),
      previousLifecycleState: previous.nextLifecycleState
    )

    #expect(
      next.lifecycle == [
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskCancel(firstTask)),
        .init(identity: testIdentity("Root", "Leaf"), operation: .taskStart(secondTask)),
      ])
  }

  @Test("stable identity reorder does not emit lifecycle deltas")
  func stableIdentityReorderDoesNotEmitLifecycleDeltas() {
    let planner = CommitPlanner()
    let previousTree = lifecycleTree(
      children: [
        lifecycleNode(testIdentity("Root", "A"), appear: ["appear-A"], disappear: ["disappear-A"]),
        lifecycleNode(testIdentity("Root", "B"), appear: ["appear-B"], disappear: ["disappear-B"]),
      ]
    )
    let nextTree = lifecycleTree(
      children: [
        lifecycleNode(testIdentity("Root", "B"), appear: ["appear-B"], disappear: ["disappear-B"]),
        lifecycleNode(testIdentity("Root", "A"), appear: ["appear-A"], disappear: ["disappear-A"]),
      ]
    )

    let previous = planner.plan(resolved: previousTree, semantics: .init())
    let next = planner.plan(
      resolved: nextTree,
      semantics: .init(),
      previousLifecycleState: previous.nextLifecycleState
    )

    #expect(next.lifecycle.isEmpty)
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
      task: task
    )
  )
}
