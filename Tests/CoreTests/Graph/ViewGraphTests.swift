import Testing

@testable import Core

@MainActor
@Suite
struct ViewGraphTests {
  @Test("applying a first snapshot emits appear and task start events")
  func firstSnapshotEmitsLifecycleEvents() {
    let graph = ViewGraph()
    let task = TaskDescriptor(id: "load", priority: .medium)
    let snapshot = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Leaf"),
          kind: .view("Leaf"),
          lifecycleMetadata: .init(
            appearHandlerIDs: ["appear-leaf"],
            disappearHandlerIDs: ["disappear-leaf"],
            task: task
          )
        )
      ]
    )

    let events = graph.applySnapshot(snapshot)

    #expect(
      events == [
        .init(
          identity: testIdentity("Root", "Leaf"),
          operation: .appear(handlerIDs: ["appear-leaf"])
        ),
        .init(
          identity: testIdentity("Root", "Leaf"),
          operation: .taskStart(task)
        ),
      ]
    )
    #expect(graph.snapshot() == snapshot)
  }

  @Test("removing a node emits task cancel before disappear")
  func removalEmitsTaskCancelBeforeDisappear() {
    let graph = ViewGraph()
    let task = TaskDescriptor(id: "load", priority: .medium)
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(
            identity: testIdentity("Root", "Leaf"),
            kind: .view("Leaf"),
            lifecycleMetadata: .init(
              appearHandlerIDs: ["appear-leaf"],
              disappearHandlerIDs: ["disappear-leaf"],
              task: task
            )
          )
        ]
      )
    )

    let events = graph.applySnapshot(
      ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root
      )
    )

    #expect(
      events == [
        .init(
          identity: testIdentity("Root", "Leaf"),
          operation: .taskCancel(task)
        ),
        .init(
          identity: testIdentity("Root", "Leaf"),
          operation: .disappear(handlerIDs: ["disappear-leaf"])
        ),
      ]
    )
  }

  @Test("graph-local dirty evaluation prefers node evaluators over the root evaluator")
  func graphLocalDirtyEvaluationUsesNodeFrontier() {
    let graph = ViewGraph()
    let snapshot = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Leaf"),
          kind: .view("Leaf")
        )
      ]
    )
    _ = graph.applySnapshot(snapshot)

    var rootEvaluations = 0
    var leafEvaluations = 0

    graph.setRootEvaluator(rootIdentity: testIdentity("Root")) {
      rootEvaluations += 1
    }
    graph.setEvaluator(for: testIdentity("Root", "Leaf")) {
      leafEvaluations += 1
    }

    graph.beginFrame()
    graph.queueDirty([testIdentity("Root", "Leaf")])
    graph.invalidate([testIdentity("Root", "Leaf")])
    let usedDirtyFrontier = graph.evaluateDirtyNodes()

    #expect(usedDirtyFrontier)
    #expect(rootEvaluations == 0)
    #expect(leafEvaluations == 1)
  }

  @Test("graph-local root dirtiness still reevaluates through the root node evaluator")
  func graphLocalRootDirtyEvaluationUsesRootNodeEvaluator() {
    let graph = ViewGraph()
    let snapshot = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root
    )
    _ = graph.applySnapshot(snapshot)

    var rootEvaluatorCalls = 0
    var rootNodeEvaluatorCalls = 0

    graph.setRootEvaluator(rootIdentity: testIdentity("Root")) {
      rootEvaluatorCalls += 1
    }
    graph.setEvaluator(for: testIdentity("Root")) {
      rootNodeEvaluatorCalls += 1
    }

    graph.beginFrame()
    graph.queueDirty([testIdentity("Root")])
    graph.invalidate([testIdentity("Root")])
    let usedDirtyFrontier = graph.evaluateDirtyNodes()

    #expect(usedDirtyFrontier)
    #expect(rootEvaluatorCalls == 0)
    #expect(rootNodeEvaluatorCalls == 1)
  }
}
