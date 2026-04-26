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

  @Test("checkpoint restore rolls back graph mutation and dependency indexes")
  func checkpointRestoreRollsBackGraphMutation() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let replacementIdentity = testIdentity("Root", "Replacement")
    let childEnvironmentKey = ObjectIdentifier(DependencyKeyA.self)
    let replacementEnvironmentKey = ObjectIdentifier(DependencyKeyB.self)
    let initialSnapshot = seedCommittedDependencyGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentities: [childIdentity]
    ) { identity, node in
      if identity == childIdentity {
        node.recordEnvironmentRead(childEnvironmentKey)
      }
    }

    let checkpoint = graph.makeCheckpoint()

    graph.beginFrame()
    let replacementNode = graph.beginEvaluation(
      identity: replacementIdentity,
      invalidator: nil
    )
    replacementNode.recordEnvironmentRead(replacementEnvironmentKey)
    let replacementSnapshot = ResolvedNode(
      identity: replacementIdentity,
      kind: .view("Replacement")
    )
    graph.finishEvaluation(
      replacementNode,
      resolved: replacementSnapshot,
      accessedStateSlots: 0
    )
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [replacementSnapshot]
      ),
      accessedStateSlots: 0
    )

    #expect(
      graph.snapshot(rootIdentity: rootIdentity).children.map(\.identity) == [
        replacementIdentity
      ])
    #expect(graph.dependencies(for: childIdentity) == nil)
    #expect(
      graph.environmentDependentIdentities(for: replacementEnvironmentKey) == [
        replacementIdentity
      ]
    )

    graph.restore(checkpoint)

    #expect(graph.snapshot() == initialSnapshot)
    #expect(graph.dependencies(for: childIdentity)?.environmentReads == [childEnvironmentKey])
    #expect(graph.dependencies(for: replacementIdentity) == nil)
    #expect(graph.environmentDependentIdentities(for: replacementEnvironmentKey).isEmpty)
    #expect(graph.liveIdentitySnapshot() == [rootIdentity, childIdentity])

    graph.beginFrame()
    let reusable = graph.reusableSnapshot(
      for: rootIdentity,
      invalidatedIdentities: [testIdentity("Unrelated")],
      environment: .init(),
      transaction: .init(),
      invalidator: nil
    )
    #expect(reusable == initialSnapshot)
  }

  @Test("checkpoint restore preserves node handlers and evaluators")
  func checkpointRestorePreservesNodeHandlersAndEvaluators() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    _ = seedCommittedDependencyGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentities: []
    )
    let node = try #require(graph.nodeForIdentity(rootIdentity))
    let restoredHandlerCalls = Counter()
    let draftHandlerCalls = Counter()
    var restoredEvaluatorCalls = 0
    var draftEvaluatorCalls = 0

    node.recordActionRegistration(
      identity: rootIdentity,
      handler: {
        restoredHandlerCalls.increment()
        return true
      },
      followUpInvalidationIdentity: nil
    )
    graph.setEvaluator(for: rootIdentity) {
      restoredEvaluatorCalls += 1
    }
    let checkpoint = graph.makeCheckpoint()

    node.recordActionRegistration(
      identity: rootIdentity,
      handler: {
        draftHandlerCalls.increment()
        return true
      },
      followUpInvalidationIdentity: nil
    )
    graph.setEvaluator(for: rootIdentity) {
      draftEvaluatorCalls += 1
    }

    graph.restore(checkpoint)

    let actionRegistry = LocalActionRegistry()
    graph.nodeForIdentity(rootIdentity)?.restoreOwnRuntimeRegistrations(
      into: RuntimeRegistrationSet(actionRegistry: actionRegistry)
    )
    #expect(actionRegistry.dispatch(identity: rootIdentity))
    #expect(restoredHandlerCalls.count == 1)
    #expect(draftHandlerCalls.count == 0)

    graph.beginFrame()
    graph.queueDirty([rootIdentity])
    graph.invalidate([rootIdentity])
    #expect(graph.evaluateDirtyNodes())
    #expect(restoredEvaluatorCalls == 1)
    #expect(draftEvaluatorCalls == 0)
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

private final class Counter {
  private(set) var count = 0

  func increment() {
    count += 1
  }
}

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

@discardableResult
@MainActor
private func seedCommittedDependencyGraph(
  graph: ViewGraph,
  rootIdentity: Identity,
  childIdentities: [Identity],
  configureChild: (Identity, ViewNode) -> Void = { _, _ in }
) -> ResolvedNode {
  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
  let childSnapshots = childIdentities.map { identity -> ResolvedNode in
    let childNode = graph.beginEvaluation(identity: identity, invalidator: nil)
    let kindName = identity.lastComponent ?? "Child"
    configureChild(identity, childNode)
    let childSnapshot = ResolvedNode(identity: identity, kind: .view(kindName))
    graph.finishEvaluation(
      childNode,
      resolved: childSnapshot,
      accessedStateSlots: 0
    )
    return childSnapshot
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
  let snapshot = graph.snapshot(rootIdentity: rootIdentity)
  _ = graph.finalizeFrame(resolved: snapshot, placed: nil)
  return snapshot
}
