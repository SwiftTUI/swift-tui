import Testing

@testable import SwiftTUICore

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

  @Test("runtime registration restore includes command and drop handlers")
  func runtimeRegistrationRestoreIncludesCommandAndDropHandlers() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let binding = KeyBinding(key: .character("s"), modifiers: .ctrl)
    let commandCounter = RegistrationCounter()
    let dropCounter = RegistrationCounter()

    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    childNode.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [
          childIdentity: [
            binding: RegisteredKeyCommand(
              binding: binding,
              description: "Save",
              isEnabled: true,
              action: { commandCounter.increment() }
            )
          ]
        ]
      )
    )
    childNode.recordDropDestinationRegistration(
      DropDestinationRegistrySnapshot(
        handlersByScope: [
          childIdentity: { _, _ in
            dropCounter.increment()
            return true
          }
        ]
      )
    )
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
    let snapshot = graph.snapshot(rootIdentity: rootIdentity)
    let commandRegistry = CommandRegistry()
    let dropDestinationRegistry = DropDestinationRegistry()
    let registrations = RuntimeRegistrationSet(
      commandRegistry: commandRegistry,
      dropDestinationRegistry: dropDestinationRegistry
    )

    graph.restoreRuntimeRegistrations(
      for: snapshot,
      into: registrations
    )

    #expect(commandRegistry.dispatch(key: binding, along: [rootIdentity, childIdentity]))
    #expect(commandCounter.count == 1)
    #expect(
      dropDestinationRegistry.dispatch(
        paths: [DroppedPath("/tmp/example")],
        along: [rootIdentity, childIdentity]
      )
    )
    #expect(dropCounter.count == 1)
  }

  @Test("runtime registration restore includes alias command and drop handlers")
  func runtimeRegistrationRestoreIncludesAliasCommandAndDropHandlers() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let aliasIdentity = testIdentity("Root", "Alias")
    let binding = KeyBinding(key: .character("a"), modifiers: .ctrl)
    let commandCounter = RegistrationCounter()
    let dropCounter = RegistrationCounter()

    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let targetNode = graph.beginEvaluation(identity: targetIdentity, invalidator: nil)
    graph.finishEvaluation(
      targetNode,
      resolved: ResolvedNode(identity: targetIdentity, kind: .view("Target")),
      accessedStateSlots: 0
    )
    let aliasNode = graph.beginEvaluation(identity: aliasIdentity, invalidator: nil)
    aliasNode.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [
          aliasIdentity: [
            binding: RegisteredKeyCommand(
              binding: binding,
              description: "Alias",
              isEnabled: true,
              action: { commandCounter.increment() }
            )
          ]
        ]
      )
    )
    aliasNode.recordDropDestinationRegistration(
      DropDestinationRegistrySnapshot(
        handlersByScope: [
          aliasIdentity: { _, _ in
            dropCounter.increment()
            return true
          }
        ]
      )
    )
    graph.finishEvaluation(
      aliasNode,
      resolved: ResolvedNode(identity: aliasIdentity, kind: .view("Alias")),
      accessedStateSlots: 0
    )
    graph.recordRegistrationAlias(
      from: aliasIdentity,
      to: targetIdentity,
      resolvedKind: .view("Target")
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: targetIdentity, kind: .view("Target"))
        ]
      ),
      accessedStateSlots: 0
    )
    let snapshot = graph.snapshot(rootIdentity: rootIdentity)
    let registrations = RuntimeRegistrationSet.scratch()

    graph.restoreRuntimeRegistrations(
      for: snapshot,
      into: registrations
    )

    #expect(
      registrations.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: binding
      ) != nil
    )
    #expect(
      registrations.commandRegistry?.dispatch(
        key: binding,
        along: [rootIdentity, aliasIdentity]
      ) == true
    )
    #expect(commandCounter.count == 1)
    #expect(
      registrations.dropDestinationRegistry?.dispatch(
        paths: [DroppedPath("/tmp/alias.txt")],
        along: [rootIdentity, aliasIdentity]
      ) == true
    )
    #expect(dropCounter.count == 1)
  }

  @Test("view graph frame draft commit restores from committed graph")
  func viewGraphFrameDraftCommitRestoresFromCommittedGraph() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let aliasIdentity = testIdentity("Root", "Alias")
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedAliasCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      targetIdentity: targetIdentity,
      aliasIdentity: aliasIdentity,
      binding: originalBinding,
      description: "Original",
      counter: originalCounter
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    #expect(
      liveRegistrations.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: originalBinding
      ) != nil
    )

    let registrationDraft = FrameHeadRegistrationDraft()
    registrationDraft.draftRegistrations.commandRegistry?.registerKeyCommand(
      at: aliasIdentity,
      binding: draftBinding,
      description: "Draft",
      isEnabled: true
    ) {
      draftCounter.increment()
    }
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: nil
    )
    graphDraft.recordDirtyEvaluationPlan(nil)
    graphDraft.commitRuntimeRegistrations(from: graph)

    #expect(
      liveRegistrations.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      liveRegistrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, aliasIdentity]
      ) == true
    )
    #expect(originalCounter.count == 1)
    #expect(draftCounter.count == 0)
  }

  @Test("view graph frame draft discard restores graph without live registry mutation")
  func viewGraphFrameDraftDiscardRestoresGraphWithoutLiveRegistryMutation() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentity: childIdentity,
      binding: originalBinding,
      description: "Original",
      counter: originalCounter
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: graph.makeCheckpoint()
    )

    graph.beginFrame()
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    childNode.recordCommandRegistration(
      commandSnapshot(
        identity: childIdentity,
        binding: draftBinding,
        description: "Draft",
        counter: draftCounter
      )
    )
    graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: childIdentity, kind: .view("Child")),
      accessedStateSlots: 0
    )
    graphDraft.recordDirtyEvaluationPlan(.init(frontierIdentities: [childIdentity]))

    graphDraft.discard(from: graph)

    #expect(
      liveRegistrations.commandRegistry?.keyCommand(
        at: childIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      liveRegistrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, childIdentity]
      ) == true
    )
    #expect(originalCounter.count == 1)

    let restoredRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: restoredRegistrations)
    #expect(
      restoredRegistrations.commandRegistry?.keyCommand(
        at: childIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      restoredRegistrations.commandRegistry?.keyCommand(
        at: childIdentity,
        matching: originalBinding
      ) != nil
    )
    #expect(draftCounter.count == 0)
  }

  @Test("checkpoint restore reverts command registration changes")
  func checkpointRestoreRevertsCommandRegistrationChanges() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentity: childIdentity,
      binding: originalBinding,
      description: "Original",
      counter: originalCounter
    )
    let checkpoint = graph.makeCheckpoint()

    graph.beginFrame()
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    childNode.recordCommandRegistration(
      commandSnapshot(
        identity: childIdentity,
        binding: draftBinding,
        description: "Draft",
        counter: draftCounter
      )
    )
    graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: childIdentity, kind: .view("Child")),
      accessedStateSlots: 0
    )

    graph.restoreCheckpoint(checkpoint)

    let snapshot = graph.snapshot(rootIdentity: rootIdentity)
    let registrations = RuntimeRegistrationSet.scratch()
    graph.restoreRuntimeRegistrations(
      for: snapshot,
      into: registrations
    )

    #expect(
      registrations.commandRegistry?.keyCommand(
        at: childIdentity,
        matching: originalBinding
      ) != nil
    )
    #expect(
      registrations.commandRegistry?.keyCommand(
        at: childIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      registrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, childIdentity]
      ) == true
    )
    #expect(originalCounter.count == 1)
    #expect(draftCounter.count == 0)
  }

  @Test("checkpoint restore preserves alias registration restore")
  func checkpointRestorePreservesAliasRegistrationRestore() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let aliasIdentity = testIdentity("Root", "Alias")
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedAliasCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      targetIdentity: targetIdentity,
      aliasIdentity: aliasIdentity,
      binding: originalBinding,
      description: "Original",
      counter: originalCounter
    )
    let checkpoint = graph.makeCheckpoint()

    graph.beginFrame()
    let aliasNode = graph.beginEvaluation(identity: aliasIdentity, invalidator: nil)
    aliasNode.recordCommandRegistration(
      commandSnapshot(
        identity: aliasIdentity,
        binding: draftBinding,
        description: "Draft",
        counter: draftCounter
      )
    )
    graph.finishEvaluation(
      aliasNode,
      resolved: ResolvedNode(identity: aliasIdentity, kind: .view("Alias")),
      accessedStateSlots: 0
    )
    graph.recordRegistrationAlias(
      from: aliasIdentity,
      to: targetIdentity,
      resolvedKind: .view("Target")
    )

    graph.restoreCheckpoint(checkpoint)

    let snapshot = graph.snapshot(rootIdentity: rootIdentity)
    let registrations = RuntimeRegistrationSet.scratch()
    graph.restoreRuntimeRegistrations(
      for: snapshot,
      into: registrations
    )

    #expect(
      registrations.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: originalBinding
      ) != nil
    )
    #expect(
      registrations.commandRegistry?.keyCommand(
        at: aliasIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      registrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, aliasIdentity]
      ) == true
    )
    #expect(originalCounter.count == 1)
    #expect(draftCounter.count == 0)
  }
}

private enum DependencyKeyA {}
private enum DependencyKeyB {}

private final class DependencyObservableBox {}

@MainActor
private final class RegistrationCounter {
  private(set) var count = 0

  func increment() {
    count += 1
  }
}

@MainActor
private func commandSnapshot(
  identity: Identity,
  binding: KeyBinding,
  description: String,
  counter: RegistrationCounter
) -> CommandRegistrySnapshot {
  CommandRegistrySnapshot(
    keyCommandsByScope: [
      identity: [
        binding: RegisteredKeyCommand(
          binding: binding,
          description: description,
          isEnabled: true,
          action: { counter.increment() }
        )
      ]
    ]
  )
}

@MainActor
private func seedCommandGraph(
  graph: ViewGraph,
  rootIdentity: Identity,
  childIdentity: Identity,
  binding: KeyBinding,
  description: String,
  counter: RegistrationCounter
) {
  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
  let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
  childNode.recordCommandRegistration(
    commandSnapshot(
      identity: childIdentity,
      binding: binding,
      description: description,
      counter: counter
    )
  )
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
  _ = graph.snapshot(rootIdentity: rootIdentity)
}

@MainActor
private func seedAliasCommandGraph(
  graph: ViewGraph,
  rootIdentity: Identity,
  targetIdentity: Identity,
  aliasIdentity: Identity,
  binding: KeyBinding,
  description: String,
  counter: RegistrationCounter
) {
  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
  let targetNode = graph.beginEvaluation(identity: targetIdentity, invalidator: nil)
  graph.finishEvaluation(
    targetNode,
    resolved: ResolvedNode(identity: targetIdentity, kind: .view("Target")),
    accessedStateSlots: 0
  )
  let aliasNode = graph.beginEvaluation(identity: aliasIdentity, invalidator: nil)
  aliasNode.recordCommandRegistration(
    commandSnapshot(
      identity: aliasIdentity,
      binding: binding,
      description: description,
      counter: counter
    )
  )
  graph.finishEvaluation(
    aliasNode,
    resolved: ResolvedNode(identity: aliasIdentity, kind: .view("Alias")),
    accessedStateSlots: 0
  )
  graph.recordRegistrationAlias(
    from: aliasIdentity,
    to: targetIdentity,
    resolvedKind: .view("Target")
  )
  graph.finishEvaluation(
    rootNode,
    resolved: ResolvedNode(
      identity: rootIdentity,
      kind: .root,
      children: [
        ResolvedNode(identity: targetIdentity, kind: .view("Target"))
      ]
    ),
    accessedStateSlots: 0
  )
  _ = graph.snapshot(rootIdentity: rootIdentity)
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
