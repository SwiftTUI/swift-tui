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

  @Test("dependency indices reindex when a node's reads change")
  func dependencyIndicesReindexOnReevaluation() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let stateKey = StateSlotKey(identity: rootIdentity, ordinal: 0)
    let environmentKeyA = ObjectIdentifier(DependencyKeyA.self)
    let environmentKeyB = ObjectIdentifier(DependencyKeyB.self)
    let observableBox = DependencyObservableBox()
    let observableID = ObjectIdentifier(observableBox)

    graph.beginFrame()
    let node = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = node.stateSlot(ordinal: 0, seed: 0)
    node.recordEnvironmentRead(environmentKeyA)
    node.recordObservableRead(observableID)
    graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root),
      accessedStateSlots: 1
    )

    let initialDependencies = try #require(graph.dependencies(for: rootIdentity))
    #expect(initialDependencies.stateSlotReads == [stateKey])
    #expect(initialDependencies.environmentReads == [environmentKeyA])
    #expect(initialDependencies.observableReads == [observableID])
    #expect(graph.stateDependentIdentities(for: stateKey) == [rootIdentity])
    #expect(graph.environmentDependentIdentities(for: environmentKeyA) == [rootIdentity])
    #expect(graph.observableDependentIdentities(for: observableID) == [rootIdentity])

    graph.beginFrame()
    let reevaluatedNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    reevaluatedNode.recordEnvironmentRead(environmentKeyB)
    graph.finishEvaluation(
      reevaluatedNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root),
      accessedStateSlots: 0
    )

    let updatedDependencies = try #require(graph.dependencies(for: rootIdentity))
    #expect(updatedDependencies.stateSlotReads.isEmpty)
    #expect(updatedDependencies.environmentReads == [environmentKeyB])
    #expect(updatedDependencies.observableReads.isEmpty)
    #expect(graph.stateDependentIdentities(for: stateKey).isEmpty)
    #expect(graph.environmentDependentIdentities(for: environmentKeyA).isEmpty)
    #expect(graph.environmentDependentIdentities(for: environmentKeyB) == [rootIdentity])
    #expect(graph.observableDependentIdentities(for: observableID).isEmpty)
  }

  @Test("dependency indices are removed when a subtree is pruned")
  func dependencyIndicesClearOnSubtreeRemoval() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let environmentKey = ObjectIdentifier(DependencyKeyA.self)

    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    childNode.recordEnvironmentRead(environmentKey)
    graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: childIdentity, kind: .view("Child")),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      ),
      accessedStateSlots: 0
    )

    #expect(graph.environmentDependentIdentities(for: environmentKey) == [childIdentity])

    graph.beginFrame()
    let updatedRootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    graph.finishEvaluation(
      updatedRootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root),
      accessedStateSlots: 0
    )

    #expect(graph.environmentDependentIdentities(for: environmentKey).isEmpty)
    #expect(graph.dependencies(for: childIdentity) == nil)
  }

  @Test("environment invalidation reevaluates only readers of the changed key")
  func environmentInvalidationUsesDependencyIndices() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let readerIdentity = testIdentity("Root", "Reader")
    let unrelatedIdentity = testIdentity("Root", "Unrelated")
    let environmentKey = ObjectIdentifier(DependencyKeyA.self)

    seedDependencyGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentities: [readerIdentity, unrelatedIdentity]
    ) { identity, node in
      if identity == readerIdentity {
        node.recordEnvironmentRead(environmentKey)
      }
    }

    var rootEvaluations = 0
    var readerEvaluations = 0
    var unrelatedEvaluations = 0
    graph.setRootEvaluator(rootIdentity: rootIdentity) {
      rootEvaluations += 1
    }
    graph.setEvaluator(for: readerIdentity) {
      readerEvaluations += 1
    }
    graph.setEvaluator(for: unrelatedIdentity) {
      unrelatedEvaluations += 1
    }

    graph.beginFrame()
    graph.invalidateEnvironmentReaders(
      within: [rootIdentity],
      changedKeys: [environmentKey]
    )
    let usedDirtyFrontier = graph.evaluateDirtyNodes()

    #expect(usedDirtyFrontier)
    #expect(rootEvaluations == 0)
    #expect(readerEvaluations == 1)
    #expect(unrelatedEvaluations == 0)
  }

  @Test("observation changes reevaluate only nodes that share the observed token")
  func observationInvalidationUsesDependencyIndices() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let triggeringIdentity = testIdentity("Root", "Triggering")
    let peerIdentity = testIdentity("Root", "Peer")
    let unrelatedIdentity = testIdentity("Root", "Unrelated")
    let sharedObservable = DependencyObservableBox()
    let unrelatedObservable = DependencyObservableBox()
    let sharedObservableID = ObjectIdentifier(sharedObservable)
    let unrelatedObservableID = ObjectIdentifier(unrelatedObservable)

    seedDependencyGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentities: [triggeringIdentity, peerIdentity, unrelatedIdentity]
    ) { identity, node in
      switch identity {
      case triggeringIdentity, peerIdentity:
        node.recordObservableRead(sharedObservableID)
      case unrelatedIdentity:
        node.recordObservableRead(unrelatedObservableID)
      default:
        break
      }
    }

    var rootEvaluations = 0
    var triggeringEvaluations = 0
    var peerEvaluations = 0
    var unrelatedEvaluations = 0
    graph.setRootEvaluator(rootIdentity: rootIdentity) {
      rootEvaluations += 1
    }
    graph.setEvaluator(for: triggeringIdentity) {
      triggeringEvaluations += 1
    }
    graph.setEvaluator(for: peerIdentity) {
      peerEvaluations += 1
    }
    graph.setEvaluator(for: unrelatedIdentity) {
      unrelatedEvaluations += 1
    }

    graph.beginFrame()
    graph.invalidate([triggeringIdentity])
    graph.queueDirtyForObservationChange(observedBy: triggeringIdentity)
    let usedDirtyFrontier = graph.evaluateDirtyNodes()

    #expect(usedDirtyFrontier)
    #expect(rootEvaluations == 0)
    #expect(triggeringEvaluations == 1)
    #expect(peerEvaluations == 1)
    #expect(unrelatedEvaluations == 0)
  }
}

private enum DependencyKeyA {}
private enum DependencyKeyB {}

private final class DependencyObservableBox {}

@MainActor
private func seedDependencyGraph(
  graph: ViewGraph,
  rootIdentity: Identity,
  childIdentities: [Identity],
  configureChild: (Identity, ViewNode) -> Void = { _, _ in }
) {
  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
  let childSnapshots = childIdentities.map { identity -> ResolvedNode in
    let childNode = graph.beginEvaluation(identity: identity, invalidator: nil)
    let kindName = identity.lastComponent ?? "Child"
    configureChild(identity, childNode)
    graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: identity, kind: .view(kindName)),
      accessedStateSlots: 0
    )
    return ResolvedNode(identity: identity, kind: .view(kindName))
  }
  graph.finishEvaluation(
    rootNode,
    resolved: ResolvedNode(
      identity: rootIdentity,
      kind: .root,
      children: childSnapshots
    ),
    accessedStateSlots: 0
  )
  _ = graph.snapshot(rootIdentity: rootIdentity)
}
