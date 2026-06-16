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
          viewNodeID: ViewNodeID(rawValue: 2),
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
          viewNodeID: ViewNodeID(rawValue: 2),
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

  @Test("graph-local suppression dirty work forms a plan without scheduler invalidation")
  func graphLocalSuppressionDirtyWorkFormsPlanWithoutSchedulerInvalidation() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let readerIdentity = testIdentity("Root", "Reader")
    let leafIdentity = testIdentity("Root", "Reader", "Leaf")
    let stableIdentity = testIdentity("Root", "Stable")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: readerIdentity,
            kind: .view("Reader"),
            children: [
              ResolvedNode(identity: leafIdentity, kind: .view("Leaf"))
            ]
          ),
          ResolvedNode(identity: stableIdentity, kind: .view("Stable")),
        ]
      )
    )

    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    graph.setEvaluator(for: readerIdentity) {}

    graph.beginFrame()
    graph.invalidateAndQueueDirtyDescendants(of: [readerIdentity])
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: []
    )

    #expect(result.plan?.frontierIdentities == [readerIdentity])
    #expect(result.diagnostics.result == "formed")
    #expect(result.diagnostics.invalidatedIdentityCount == 0)
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 0)
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

  @Test("unmapped invalidation falls back to root evaluation")
  func unmappedInvalidationFallsBackToRootEvaluation() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root
      )
    )

    var rootEvaluations = 0
    graph.setRootEvaluator(rootIdentity: rootIdentity) {
      rootEvaluations += 1
    }

    graph.beginFrame()
    graph.invalidate([testIdentity("Root", "RemovedAlias")])

    #expect(graph.hasDirtyWork)
    #expect(graph.evaluateDirtyNodes() == false)
    #expect(rootEvaluations == 1)

    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
    #expect(!graph.hasDirtyWork)
  }

  @Test("dirty-plan diagnostics identify unmapped invalidation fallback")
  func dirtyPlanDiagnosticsIdentifyUnmappedInvalidationFallback() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let removedIdentity = testIdentity("Root", "RemovedAlias")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root
      )
    )

    graph.beginFrame()
    graph.invalidate([removedIdentity])

    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: [removedIdentity]
    )

    #expect(result.plan == nil)
    #expect(result.diagnostics.result == "nil_unmapped_invalidated_identity")
    #expect(result.diagnostics.invalidatedIdentityCount == 1)
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 1)
    #expect(result.diagnostics.unmappedInvalidatedIdentitySample == [removedIdentity])
  }

  @Test("presentation portal descendant invalidation maps to existing overlay subtree")
  func presentationPortalInvalidationMapsToExistingOverlaySubtree() {
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let bodyIdentity = testPresentationPortalBodyIdentity(
      portalRootIdentity: portalRootIdentity
    )
    let staleBodyDescendant = bodyIdentity.child("StaleResolvedLeaf")

    seedPortalGraph(
      graph: graph,
      portalRootIdentity: portalRootIdentity,
      bodyIdentity: bodyIdentity
    )
    graph.setEvaluator(for: bodyIdentity) {}

    let translated = graph.translatePresentationPortalInvalidations(
      [staleBodyDescendant],
      portalRootIdentity: portalRootIdentity
    )

    #expect(translated == [bodyIdentity])

    graph.beginFrame()
    graph.invalidateAndQueueDirty(translated)
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )

    #expect(result.plan?.frontierIdentities == [bodyIdentity])
    #expect(result.diagnostics.result == "formed")
    #expect(result.diagnostics.invalidatedIdentityCount == 1)
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 0)
  }

  @Test("active presentation portal entry maps slash-flattened stale identity")
  func activePresentationPortalEntryMapsSlashFlattenedStaleIdentity() {
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let entryIdentity = testPresentationPortalEntryIdentity(
      portalRootIdentity: portalRootIdentity,
      entryID: "sheet/source:Root/Layout[0]#sheet"
    )
    let bodyIdentity = entryIdentity.child("body")
    let staleFlattenedIdentity = Identity(
      components:
        bodyIdentity
        .child("StaleResolvedLeaf")
        .path
        .split(separator: "/")
        .map(String.init)
    )

    seedPortalGraph(
      graph: graph,
      portalRootIdentity: portalRootIdentity,
      bodyIdentity: bodyIdentity
    )
    graph.setEvaluator(for: bodyIdentity) {}

    let translated = graph.translatePresentationPortalInvalidations(
      [staleFlattenedIdentity],
      portalRootIdentity: portalRootIdentity
    )

    #expect(translated == [bodyIdentity])

    graph.beginFrame()
    graph.invalidateAndQueueDirty(translated)
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )

    #expect(result.plan?.frontierIdentities == [bodyIdentity])
    #expect(result.diagnostics.result == "formed")
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 0)
  }

  @Test("unknown presentation-like invalidation remains unmapped")
  func unknownPresentationLikeInvalidationRemainsUnmapped() {
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let inactivePortalRootIdentity = Identity(
      components: ["__TerminalUIPortalHost", "InactiveRoot"]
    )
    let unknownBodyDescendant = testPresentationPortalBodyIdentity(
      portalRootIdentity: inactivePortalRootIdentity,
      entryID: "missing-sheet"
    ).child("StaleResolvedLeaf")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: portalRootIdentity,
        kind: .view("PresentationPortalRoot")
      )
    )

    let translated = graph.translatePresentationPortalInvalidations(
      [unknownBodyDescendant],
      portalRootIdentity: portalRootIdentity
    )

    #expect(translated == [unknownBodyDescendant])

    graph.beginFrame()
    graph.invalidateAndQueueDirty(translated)
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )

    #expect(result.plan == nil)
    #expect(result.diagnostics.result == "nil_unmapped_invalidated_identity")
    #expect(result.diagnostics.invalidatedIdentityCount == 1)
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 1)
    #expect(result.diagnostics.unmappedInvalidatedIdentitySample == [unknownBodyDescendant])
  }

  @Test("presentation entry under live portal root stays unmapped when the overlay host is absent")
  func presentationEntryUnderLivePortalRootStaysUnmappedWhenHostIsAbsent() {
    // Regression guard for the sheet-settle cone: an overlay-entry invalidation
    // whose overlay host is not yet materialized must NOT fall back to the
    // portal root. The portal root is the graph root and an ancestor of the
    // content, so mapping onto it swept the entire disjoint background into the
    // reuse-conflict cone. It now stays unmapped (a `.all` fallback, which is
    // already the case on these force-root frames), leaving the background
    // reuse-eligible; `installPresentationPortalEvaluator` re-resolves the
    // portal root regardless.
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let staleEntryDescendant = testPresentationPortalBodyIdentity(
      portalRootIdentity: portalRootIdentity,
      entryID: "missing-sheet"
    ).child("StaleResolvedLeaf")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: portalRootIdentity,
        kind: .view("PresentationPortalRoot")
      )
    )
    graph.setEvaluator(for: portalRootIdentity) {}

    let translated = graph.translatePresentationPortalInvalidations(
      [staleEntryDescendant],
      portalRootIdentity: portalRootIdentity
    )

    #expect(translated == [staleEntryDescendant])

    graph.beginFrame()
    graph.invalidateAndQueueDirty(translated)
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )

    #expect(result.plan == nil)
    #expect(result.diagnostics.result == "nil_unmapped_invalidated_identity")
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 1)
  }

  @Test("inactive presentation entry under live overlay host maps to overlay host")
  func inactivePresentationEntryUnderLiveOverlayHostMapsToOverlayHost() {
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let bodyIdentity = testPresentationPortalBodyIdentity(
      portalRootIdentity: portalRootIdentity
    )
    let overlayHostIdentity = testPresentationOverlayHostIdentity(
      portalRootIdentity: portalRootIdentity
    )
    let staleMissingEntryDescendant = testPresentationPortalBodyIdentity(
      portalRootIdentity: portalRootIdentity,
      entryID: "missing-sheet"
    ).child("StaleResolvedLeaf")

    seedPortalGraph(
      graph: graph,
      portalRootIdentity: portalRootIdentity,
      bodyIdentity: bodyIdentity
    )
    graph.setEvaluator(for: overlayHostIdentity) {}

    let translated = graph.translatePresentationPortalInvalidations(
      [staleMissingEntryDescendant],
      portalRootIdentity: portalRootIdentity
    )

    #expect(translated == [overlayHostIdentity])

    graph.beginFrame()
    graph.invalidateAndQueueDirty(translated)
    let result = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )

    #expect(result.plan?.frontierIdentities == [overlayHostIdentity])
    #expect(result.diagnostics.result == "formed")
    #expect(result.diagnostics.unmappedInvalidatedIdentityCount == 0)
  }

  @Test("mapped presentation portal invalidation commits scoped runtime registrations")
  func mappedPresentationPortalInvalidationCommitsScopedRuntimeRegistrations() {
    let graph = ViewGraph()
    let portalRootIdentity = testPresentationPortalRootIdentity()
    let bodyIdentity = testPresentationPortalBodyIdentity(
      portalRootIdentity: portalRootIdentity
    )
    let staleBodyDescendant = bodyIdentity.child("StaleResolvedLeaf")
    let binding = KeyBinding(key: .character("p"), modifiers: .ctrl)
    let namespace = MatchedGeometryNamespace(0)
    let originalCommandCounter = RegistrationCounter()
    let updatedCommandCounter = RegistrationCounter()
    let actionCounter = RegistrationCounter()
    let lifecycleCounter = RegistrationCounter()

    seedPortalRegistrationGraph(
      graph: graph,
      portalRootIdentity: portalRootIdentity,
      bodyIdentity: bodyIdentity,
      binding: binding,
      commandDescription: "Original",
      commandCounter: originalCommandCounter,
      actionCounter: actionCounter,
      lifecycleCounter: lifecycleCounter,
      namespace: namespace
    )
    let resolved = graph.snapshot(rootIdentity: portalRootIdentity)
    _ = graph.finalizeFrame(
      rootIdentity: portalRootIdentity,
      resolved: resolved,
      placed: nil
    )

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: graph.makeCheckpoint(),
      publicationDiagnosticsEnabled: true
    )
    graph.setEvaluator(for: bodyIdentity) {
      let bodyNode = graph.beginEvaluation(identity: bodyIdentity, invalidator: nil)
      recordPortalRuntimeRegistrations(
        on: bodyNode,
        identity: bodyIdentity,
        binding: binding,
        commandDescription: "Updated",
        commandCounter: updatedCommandCounter,
        actionCounter: actionCounter,
        lifecycleCounter: lifecycleCounter,
        namespace: namespace
      )
      graph.finishEvaluation(
        bodyNode,
        resolved: ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody")),
        accessedStateSlots: 0
      )
    }

    graph.beginFrame()
    let translated = graph.translatePresentationPortalInvalidations(
      [staleBodyDescendant],
      portalRootIdentity: portalRootIdentity
    )
    graph.invalidateAndQueueDirty(translated)
    let dirtyEvaluation = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: translated
    )
    graphDraft.recordDirtyEvaluationPlan(
      dirtyEvaluation.plan,
      diagnostics: dirtyEvaluation.diagnostics
    )
    #expect(graph.evaluateDirtyNodes(using: dirtyEvaluation.plan))
    let scopedResolved = graph.snapshot(rootIdentity: portalRootIdentity)
    _ = graph.finalizeFrame(
      rootIdentity: portalRootIdentity,
      resolved: scopedResolved,
      placed: nil
    )

    let diagnostics = graphDraft.commitRuntimeRegistrations(from: graph)

    #expect(diagnostics.publication.publicationMode == "subtrees")
    #expect(diagnostics.publication.dirtyPlanResult == "formed")
    #expect(diagnostics.publication.subtreeRootCount == 1)
    #expect(diagnostics.publication.invalidatedIdentityCount == 1)
    #expect(diagnostics.publication.unmappedInvalidatedIdentityCount == 0)
    #expect(liveRegistrations.actionRegistry?.hasHandler(identity: bodyIdentity) == true)
    #expect(
      liveRegistrations.defaultFocusRegistry?.snapshot().candidates.map(\.identity)
        == [bodyIdentity]
    )
    #expect(
      liveRegistrations.focusBindingRegistry?.snapshot().map(\.identity)
        == [bodyIdentity]
    )
    #expect(
      Set(
        liveRegistrations.lifecycleRegistry?
          .snapshot()
          .appearRegistrations
          .values
          .map(\.identity) ?? []
      ) == [bodyIdentity]
    )
    #expect(
      liveRegistrations.taskRegistry?.registration(for: bodyIdentity)?.descriptor
        == testPortalTaskDescriptor(for: bodyIdentity)
    )
    #expect(
      liveRegistrations.commandRegistry?
        .keyCommand(at: bodyIdentity, matching: binding)?
        .description == "Updated"
    )
    #expect(
      liveRegistrations.commandRegistry?.dispatch(
        key: binding,
        along: [portalRootIdentity, bodyIdentity]
      ) == true
    )
    #expect(liveRegistrations.actionRegistry?.dispatch(identity: bodyIdentity) == true)
    #expect(updatedCommandCounter.count == 1)
    #expect(originalCommandCounter.count == 0)
    #expect(actionCounter.count == 1)
    #expect(lifecycleCounter.count == 0)
  }

  @Test(
    "characterization: mapped invalidation without graph-local dirt falls back to root evaluation")
  func mappedInvalidationWithoutDirtyCauseFallsBackToRootEvaluation() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )

    var rootEvaluations = 0
    var childEvaluations = 0
    graph.setRootEvaluator(rootIdentity: rootIdentity) {
      rootEvaluations += 1
    }
    graph.setEvaluator(for: childIdentity) {
      childEvaluations += 1
    }

    graph.beginFrame()
    graph.invalidate([childIdentity])

    #expect(graph.evaluateDirtyNodes() == false)
    #expect(rootEvaluations == 1)
    #expect(childEvaluations == 0)
  }

  @Test("disabled selective evaluation diagnostics keep invalidation samples")
  func disabledSelectiveEvaluationDiagnosticsKeepInvalidationSamples() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let unknownIdentity = testIdentity("Detached", "Child")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )

    let diagnostics = graph.disabledSelectiveEvaluationPlanDiagnostics(
      invalidatedIdentities: [childIdentity, unknownIdentity],
      selectiveEvaluationDisabledReasons: [
        "pressed_changed",
        "root_invalidated",
      ]
    )

    #expect(diagnostics.result == "nil_selective_evaluation_disabled")
    #expect(diagnostics.frontierRootCount == 0)
    #expect(diagnostics.invalidatedIdentityCount == 2)
    #expect(diagnostics.unmappedInvalidatedIdentityCount == 1)
    #expect(diagnostics.unmappedInvalidatedIdentitySample == [unknownIdentity])
    #expect(
      diagnostics.selectiveEvaluationDisabledReasons == [
        "pressed_changed",
        "root_invalidated",
      ]
    )
  }

  @Test("ViewNodeID is stable for live identities and reminted after removal")
  func viewNodeIDTracksRuntimeLifetime() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: childIdentity,
            kind: .view("Child")
          )
        ]
      )
    )
    let firstIDs = graph.debugTotalStateSnapshot().nodeIDByIdentity
    let firstRootID = firstIDs[rootIdentity]
    let firstChildID = firstIDs[childIdentity]

    #expect(firstRootID != nil)
    #expect(firstChildID != nil)
    #expect(firstRootID != firstChildID)

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: childIdentity,
            kind: .view("Child")
          )
        ]
      )
    )
    let reappliedIDs = graph.debugTotalStateSnapshot().nodeIDByIdentity
    #expect(reappliedIDs[rootIdentity] == firstRootID)
    #expect(reappliedIDs[childIdentity] == firstChildID)

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root
      )
    )
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: childIdentity,
            kind: .view("Child")
          )
        ]
      )
    )

    let remountedIDs = graph.debugTotalStateSnapshot().nodeIDByIdentity
    #expect(remountedIDs[rootIdentity] == firstRootID)
    #expect(remountedIDs[childIdentity] != firstChildID)
  }

  @Test("dependency indices reindex when a node's reads change")
  func dependencyIndicesReindexOnReevaluation() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let environmentKeyA = ObjectIdentifier(DependencyKeyA.self)
    let environmentKeyB = ObjectIdentifier(DependencyKeyB.self)
    let observableBox = DependencyObservableBox()
    let observableID = ObjectIdentifier(observableBox)

    graph.beginFrame()
    let node = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let stateKey = StateSlotKey(owner: node.viewNodeID, ordinal: 0)
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

  @Test("characterization: observation fan-out uses object tokens")
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

  @Test("characterization: observable environment fan-out uses object tokens")
  func observableEnvironmentInvalidationUsesObjectTokensSeparateFromEnvironmentKeys() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let triggeringIdentity = testIdentity("Root", "Triggering")
    let peerIdentity = testIdentity("Root", "Peer")
    let unrelatedIdentity = testIdentity("Root", "Unrelated")
    let environmentKey = ObjectIdentifier(DependencyKeyA.self)
    let sharedObservable = DependencyObservableBox()
    let unrelatedObservable = DependencyObservableBox()
    let sharedObservableID = ObjectIdentifier(sharedObservable)
    let unrelatedObservableID = ObjectIdentifier(unrelatedObservable)

    seedDependencyGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentities: [triggeringIdentity, peerIdentity, unrelatedIdentity]
    ) { identity, node in
      node.recordEnvironmentRead(environmentKey)
      switch identity {
      case triggeringIdentity, peerIdentity:
        node.recordObservableRead(sharedObservableID)
      case unrelatedIdentity:
        node.recordObservableRead(unrelatedObservableID)
      default:
        break
      }
    }

    #expect(
      graph.environmentDependentIdentities(for: environmentKey) == [
        triggeringIdentity,
        peerIdentity,
        unrelatedIdentity,
      ]
    )
    #expect(
      graph.observableDependentIdentities(for: sharedObservableID) == [
        triggeringIdentity,
        peerIdentity,
      ]
    )

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

  @Test("runtime registration restore includes same-structural-path command and drop handlers")
  func runtimeRegistrationRestoreIncludesSameStructuralPathCommandAndDropHandlers() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let contributorIdentity = testIdentity("Root", "Contributor")
    let structuralPath = StructuralPath(identity: testIdentity("Root", "Slot"))
    let binding = KeyBinding(key: .character("a"), modifiers: .ctrl)
    let commandCounter = RegistrationCounter()
    let dropCounter = RegistrationCounter()

    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let targetNode = graph.beginEvaluation(identity: targetIdentity, invalidator: nil)
    graph.finishEvaluation(
      targetNode,
      resolved: ResolvedNode(
        identity: targetIdentity,
        structuralPath: structuralPath,
        kind: .view("Target")
      ),
      accessedStateSlots: 0
    )
    let contributorNode = graph.beginEvaluation(identity: contributorIdentity, invalidator: nil)
    contributorNode.recordCommandRegistration(
      CommandRegistrySnapshot(
        keyCommandsByScope: [
          contributorIdentity: [
            binding: RegisteredKeyCommand(
              binding: binding,
              description: "Contributor",
              isEnabled: true,
              action: { commandCounter.increment() }
            )
          ]
        ]
      )
    )
    contributorNode.recordDropDestinationRegistration(
      DropDestinationRegistrySnapshot(
        handlersByScope: [
          contributorIdentity: { _, _ in
            dropCounter.increment()
            return true
          }
        ]
      )
    )
    graph.finishEvaluation(
      contributorNode,
      resolved: ResolvedNode(
        identity: targetIdentity,
        structuralPath: structuralPath,
        kind: .view("Target")
      ),
      accessedStateSlots: 0
    )
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(
            identity: targetIdentity,
            structuralPath: structuralPath,
            kind: .view("Target")
          )
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
        at: contributorIdentity,
        matching: binding
      ) != nil
    )
    #expect(
      registrations.commandRegistry?.dispatch(
        key: binding,
        along: [rootIdentity, contributorIdentity]
      ) == true
    )
    #expect(commandCounter.count == 1)
    #expect(
      registrations.dropDestinationRegistry?.dispatch(
        paths: [DroppedPath("/tmp/contributor.txt")],
        along: [rootIdentity, contributorIdentity]
      ) == true
    )
    #expect(dropCounter.count == 1)
  }

  @Test("view graph frame draft commit restores from committed graph")
  func viewGraphFrameDraftCommitRestoresFromCommittedGraph() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let contributorIdentity = testIdentity("Root", "Contributor")
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedStructuralPathContributorCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      targetIdentity: targetIdentity,
      contributorIdentity: contributorIdentity,
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
        at: contributorIdentity,
        matching: originalBinding
      ) != nil
    )

    let registrationDraft = FrameHeadRegistrationDraft()
    registrationDraft.draftRegistrations.commandRegistry?.registerKeyCommand(
      at: contributorIdentity,
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
        at: contributorIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      liveRegistrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, contributorIdentity]
      ) == true
    )
    #expect(originalCounter.count == 1)
    #expect(draftCounter.count == 0)
  }

  @Test("frame draft publication diagnostics describe subtree commit")
  func frameDraftPublicationDiagnosticsDescribeSubtreeCommit() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    seedCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      childIdentity: childIdentity,
      binding: KeyBinding(key: .character("x"), modifiers: .ctrl),
      description: "Original",
      counter: RegistrationCounter()
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
    graph.setEvaluator(for: childIdentity) {}

    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    let graphDraft = ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: graph.makeCheckpoint(),
      publicationDiagnosticsEnabled: true
    )

    graph.beginFrame()
    graph.invalidateAndQueueDirty([childIdentity])
    let dirtyEvaluation = graph.selectiveDirtyEvaluationPlanWithDiagnostics(
      invalidatedIdentities: [childIdentity]
    )
    graphDraft.recordDirtyEvaluationPlan(
      dirtyEvaluation.plan,
      diagnostics: dirtyEvaluation.diagnostics
    )
    graphDraft.recordPreparedCheckpoint(from: graph)

    let diagnostics = graphDraft.commitRuntimeRegistrations(from: graph)

    #expect(diagnostics.publication.publicationMode == "subtrees")
    #expect(diagnostics.publication.dirtyPlanResult == "formed")
    #expect(diagnostics.publication.subtreeRootCount == 1)
    #expect(diagnostics.publication.restoredNodeCount == 1)
    #expect(diagnostics.publication.invalidatedIdentityCount == 1)
    #expect(diagnostics.publication.unmappedInvalidatedIdentityCount == 0)
    #expect(diagnostics.publication.graphCheckpointBaselineNodeCount == 2)
    #expect(diagnostics.publication.graphCheckpointPreparedNodeCount == 2)
    #expect(
      diagnostics.publication.graphCheckpointDirtySubtreeCandidateNodeCount == 1
    )
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
    let childNodeID = graph.debugTotalStateSnapshot().nodeIDByIdentity[childIdentity]!
    graphDraft.recordDirtyEvaluationPlan(
      .init(frontierNodeIDs: [childNodeID], frontierIdentities: [childIdentity])
    )

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

  @Test("checkpoint restore preserves same-structural-path registration restore")
  func checkpointRestorePreservesSameStructuralPathRegistrationRestore() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let targetIdentity = testIdentity("Root", "Target")
    let contributorIdentity = testIdentity("Root", "Contributor")
    let structuralPath = StructuralPath(identity: testIdentity("Root", "Slot"))
    let originalBinding = KeyBinding(key: .character("o"), modifiers: .ctrl)
    let draftBinding = KeyBinding(key: .character("d"), modifiers: .ctrl)
    let originalCounter = RegistrationCounter()
    let draftCounter = RegistrationCounter()

    seedStructuralPathContributorCommandGraph(
      graph: graph,
      rootIdentity: rootIdentity,
      targetIdentity: targetIdentity,
      contributorIdentity: contributorIdentity,
      binding: originalBinding,
      description: "Original",
      counter: originalCounter
    )
    let checkpoint = graph.makeCheckpoint()

    graph.beginFrame()
    let contributorNode = graph.beginEvaluation(identity: contributorIdentity, invalidator: nil)
    contributorNode.recordCommandRegistration(
      commandSnapshot(
        identity: contributorIdentity,
        binding: draftBinding,
        description: "Draft",
        counter: draftCounter
      )
    )
    graph.finishEvaluation(
      contributorNode,
      resolved: ResolvedNode(
        identity: targetIdentity,
        structuralPath: structuralPath,
        kind: .view("Target")
      ),
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
        at: contributorIdentity,
        matching: originalBinding
      ) != nil
    )
    #expect(
      registrations.commandRegistry?.keyCommand(
        at: contributorIdentity,
        matching: draftBinding
      ) == nil
    )
    #expect(
      registrations.commandRegistry?.dispatch(
        key: originalBinding,
        along: [rootIdentity, contributorIdentity]
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

private func testPresentationPortalRootIdentity() -> Identity {
  Identity(components: ["__TerminalUIPortalHost", "Root"])
}

private func testPresentationPortalBodyIdentity(
  portalRootIdentity: Identity,
  entryID: String = "sheet"
) -> Identity {
  testPresentationPortalEntryIdentity(
    portalRootIdentity: portalRootIdentity,
    entryID: entryID
  )
  .child("body")
}

private func testPresentationPortalEntryIdentity(
  portalRootIdentity: Identity,
  entryID: String = "sheet"
) -> Identity {
  testPresentationOverlayHostIdentity(portalRootIdentity: portalRootIdentity)
    .child("entry:\(entryID)")
}

private func testPresentationOverlayHostIdentity(
  portalRootIdentity: Identity
) -> Identity {
  portalRootIdentity
    .child("PortalHost")
    .child("overlays")
}

@MainActor
private func seedPortalGraph(
  graph: ViewGraph,
  portalRootIdentity: Identity,
  bodyIdentity: Identity
) {
  let hostIdentity = portalRootIdentity.child("PortalHost")
  let overlaysIdentity = hostIdentity.child("overlays")
  let entryIdentity = bodyIdentity.parent!

  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: portalRootIdentity, invalidator: nil)
  let hostNode = graph.beginEvaluation(identity: hostIdentity, invalidator: nil)
  let overlaysNode = graph.beginEvaluation(identity: overlaysIdentity, invalidator: nil)
  let entryNode = graph.beginEvaluation(identity: entryIdentity, invalidator: nil)
  let bodyNode = graph.beginEvaluation(identity: bodyIdentity, invalidator: nil)
  graph.finishEvaluation(
    bodyNode,
    resolved: ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody")),
    accessedStateSlots: 0
  )
  graph.finishEvaluation(
    entryNode,
    resolved: ResolvedNode(
      identity: entryIdentity,
      kind: .view("Sheet"),
      children: [
        ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody"))
      ]
    ),
    accessedStateSlots: 0
  )
  graph.finishEvaluation(
    overlaysNode,
    resolved: ResolvedNode(
      identity: overlaysIdentity,
      kind: .view("OverlayStackOverlays"),
      children: [
        ResolvedNode(
          identity: entryIdentity,
          kind: .view("Sheet"),
          children: [
            ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody"))
          ]
        )
      ]
    ),
    accessedStateSlots: 0
  )
  graph.finishEvaluation(
    hostNode,
    resolved: ResolvedNode(
      identity: hostIdentity,
      kind: .view("PortalHost"),
      children: [
        ResolvedNode(
          identity: overlaysIdentity,
          kind: .view("OverlayStackOverlays"),
          children: [
            ResolvedNode(
              identity: entryIdentity,
              kind: .view("Sheet"),
              children: [
                ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody"))
              ]
            )
          ]
        )
      ]
    ),
    accessedStateSlots: 0
  )
  graph.finishEvaluation(
    rootNode,
    resolved: ResolvedNode(
      identity: portalRootIdentity,
      kind: .view("PresentationPortalRoot"),
      children: [
        ResolvedNode(
          identity: hostIdentity,
          kind: .view("PortalHost"),
          children: [
            ResolvedNode(
              identity: overlaysIdentity,
              kind: .view("OverlayStackOverlays"),
              children: [
                ResolvedNode(
                  identity: entryIdentity,
                  kind: .view("Sheet"),
                  children: [
                    ResolvedNode(identity: bodyIdentity, kind: .view("SheetBody"))
                  ]
                )
              ]
            )
          ]
        )
      ]
    ),
    accessedStateSlots: 0
  )
  _ = graph.snapshot(rootIdentity: portalRootIdentity)
}

@MainActor
private func seedPortalRegistrationGraph(
  graph: ViewGraph,
  portalRootIdentity: Identity,
  bodyIdentity: Identity,
  binding: KeyBinding,
  commandDescription: String,
  commandCounter: RegistrationCounter,
  actionCounter: RegistrationCounter,
  lifecycleCounter: RegistrationCounter,
  namespace: MatchedGeometryNamespace
) {
  seedPortalGraph(
    graph: graph,
    portalRootIdentity: portalRootIdentity,
    bodyIdentity: bodyIdentity
  )
  let bodyNode = graph.nodeForIdentity(bodyIdentity)!
  recordPortalRuntimeRegistrations(
    on: bodyNode,
    identity: bodyIdentity,
    binding: binding,
    commandDescription: commandDescription,
    commandCounter: commandCounter,
    actionCounter: actionCounter,
    lifecycleCounter: lifecycleCounter,
    namespace: namespace
  )
}

@MainActor
private func recordPortalRuntimeRegistrations(
  on node: ViewNode,
  identity: Identity,
  binding: KeyBinding,
  commandDescription: String,
  commandCounter: RegistrationCounter,
  actionCounter: RegistrationCounter,
  lifecycleCounter: RegistrationCounter,
  namespace: MatchedGeometryNamespace
) {
  node.beginRegistrationCapture()
  defer {
    node.endRegistrationCapture()
  }

  node.recordActionRegistration(
    identity: identity,
    handler: {
      actionCounter.increment()
      return true
    },
    followUpInvalidationIdentity: nil
  )
  node.recordDefaultFocus(
    DefaultFocusCandidateRegistrationSnapshot(namespace: namespace, identity: identity)
  )
  node.recordFocusBindingRegistration(
    FocusBindingRegistrationSnapshot(
      identity: identity,
      bindingKey: FocusBindingKey(
        ownerNodeID: node.viewNodeID,
        suffix: .stateSlot(ordinal: 0)
      ),
      bindingID: "binding-\(identity.path)",
      hasPendingRequest: false,
      isSelected: false,
      applyRuntimeFocus: { _ in false }
    )
  )
  node.recordLifecycleAppearRegistration(
    LifecycleHandlerRegistration(
      identity: identity,
      key: LifecycleHandlerKey(
        ownerNodeID: node.viewNodeID,
        suffix: .appear(ordinal: 0)
      )
    ) {
      lifecycleCounter.increment()
    }
  )
  node.recordTaskRegistration(
    identity: identity,
    registration: TaskRegistration(
      descriptor: testPortalTaskDescriptor(for: identity),
      operation: {}
    )
  )
  node.recordCommandRegistration(
    commandSnapshot(
      identity: identity,
      binding: binding,
      description: commandDescription,
      counter: commandCounter
    )
  )
}

private func testPortalTaskDescriptor(
  for identity: Identity
) -> TaskDescriptor {
  TaskDescriptor(id: "task-\(identity.path)", priority: .medium)
}

@MainActor
private func seedStructuralPathContributorCommandGraph(
  graph: ViewGraph,
  rootIdentity: Identity,
  targetIdentity: Identity,
  contributorIdentity: Identity,
  binding: KeyBinding,
  description: String,
  counter: RegistrationCounter
) {
  let structuralPath = StructuralPath(identity: testIdentity("Root", "Slot"))

  graph.beginFrame()
  let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
  let targetNode = graph.beginEvaluation(identity: targetIdentity, invalidator: nil)
  graph.finishEvaluation(
    targetNode,
    resolved: ResolvedNode(
      identity: targetIdentity,
      structuralPath: structuralPath,
      kind: .view("Target")
    ),
    accessedStateSlots: 0
  )
  let contributorNode = graph.beginEvaluation(identity: contributorIdentity, invalidator: nil)
  contributorNode.recordCommandRegistration(
    commandSnapshot(
      identity: contributorIdentity,
      binding: binding,
      description: description,
      counter: counter
    )
  )
  graph.finishEvaluation(
    contributorNode,
    resolved: ResolvedNode(
      identity: targetIdentity,
      structuralPath: structuralPath,
      kind: .view("Target")
    ),
    accessedStateSlots: 0
  )
  graph.finishEvaluation(
    rootNode,
    resolved: ResolvedNode(
      identity: rootIdentity,
      kind: .root,
      children: [
        ResolvedNode(
          identity: targetIdentity,
          structuralPath: structuralPath,
          kind: .view("Target")
        )
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
