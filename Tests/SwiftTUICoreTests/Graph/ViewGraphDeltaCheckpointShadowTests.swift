import Testing

@testable import SwiftTUICore

@MainActor
@Suite("ViewGraph delta checkpoint shadow")
struct ViewGraphDeltaCheckpointShadowTests {
  @Test("shadow summary records touched nodes while full checkpoint still restores")
  func shadowSummaryRecordsTouchedNodesWhileFullCheckpointStillRestores() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let siblingIdentity = testIdentity("Root", "Sibling")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child")),
          ResolvedNode(identity: siblingIdentity, kind: .view("Sibling")),
        ]
      )
    )

    let baseline = graph.debugTotalStateSnapshot()
    let childNodeID = baseline.nodeIDByIdentity[childIdentity]!
    let siblingNodeID = baseline.nodeIDByIdentity[siblingIdentity]!
    let draft = makeDraft(graph)

    graph.beginFrame()
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: childIdentity, kind: .view("ChildUpdated")),
      accessedStateSlots: 0
    )
    draft.recordPreparedCheckpoint(from: graph)

    let summary = draft.debugDeltaCheckpointSummary
    #expect(summary?.baselineNodeCount == 3)
    #expect(summary?.preparedNodeCount == 3)
    #expect(summary?.createdNodeIDs.isEmpty == true)
    #expect(summary?.removedNodeIDs.isEmpty == true)
    #expect(summary?.touchedNodeIDs.contains(childNodeID) == true)
    #expect(summary?.touchedNodeIDs.contains(siblingNodeID) == false)
    #expect((summary?.graphMutationEpochDelta ?? 0) > 0)

    #expect(graph.debugTotalStateSnapshot() != baseline)
    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
  }

  @Test("guarded delta restores baseline and prepared state")
  func guardedDeltaRestoresBaselineAndPreparedState() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let siblingIdentity = testIdentity("Root", "Sibling")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child")),
          ResolvedNode(identity: siblingIdentity, kind: .view("Sibling")),
        ]
      )
    )

    let baseline = graph.debugTotalStateSnapshot()
    let draft = makeDraft(graph)

    updateNode(
      graph,
      identity: childIdentity,
      kind: .view("ChildUpdated")
    )
    draft.recordPreparedCheckpoint(from: graph)
    let prepared = graph.debugTotalStateSnapshot()

    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .baseline)
    )

    draft.materializePreparedState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == prepared)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .prepared)
    )
  }

  @Test("guarded delta restores created and removed node state")
  func guardedDeltaRestoresCreatedAndRemovedNodeState() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let insertedIdentity = testIdentity("Root", "Inserted")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )

    let baseline = graph.debugTotalStateSnapshot()
    let draft = makeDraft(graph)

    updateNode(
      graph,
      identity: rootIdentity,
      kind: .root,
      children: [
        ResolvedNode(identity: insertedIdentity, kind: .view("Inserted"))
      ]
    )
    draft.recordPreparedCheckpoint(from: graph)
    let prepared = graph.debugTotalStateSnapshot()

    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .baseline)
    )

    draft.materializePreparedState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == prepared)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .prepared)
    )
  }

  @Test("guarded delta survives materialize suspend cycles with preserved dirty overlay")
  func guardedDeltaSurvivesMaterializeSuspendCyclesWithPreservedDirtyOverlay() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let siblingIdentity = testIdentity("Root", "Sibling")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child")),
          ResolvedNode(identity: siblingIdentity, kind: .view("Sibling")),
        ]
      )
    )
    graph.queueDirty([siblingIdentity])

    let baseline = graph.debugTotalStateSnapshot()
    let draft = makeDraft(graph)

    updateNode(
      graph,
      identity: childIdentity,
      kind: .view("ChildUpdated")
    )
    draft.recordPreparedCheckpoint(from: graph)

    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .baseline)
    )

    draft.materializePreparedState(
      in: graph,
      preservingCurrentStateMutations: true
    )
    #expect(
      graph.debugTotalStateSnapshot().graphLocalDirtyIdentities.contains(
        siblingIdentity
      )
    )
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .prepared)
    )

    draft.restoreBaselineState(
      in: graph,
      preservingCurrentStateMutations: true
    )
    #expect(
      graph.debugTotalStateSnapshot().graphLocalDirtyIdentities.contains(
        siblingIdentity
      )
    )
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .baseline)
    )

    draft.materializePreparedState(
      in: graph,
      preservingCurrentStateMutations: true
    )
    #expect(
      graph.debugTotalStateSnapshot().graphLocalDirtyIdentities.contains(
        siblingIdentity
      )
    )
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult == .delta(target: .prepared)
    )
  }

  @Test("large near-full delta restore uses budget fallback")
  func largeNearFullDeltaRestoreUsesBudgetFallback() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentities = (0..<40).map { index in
      testIdentity("Root", "Child\(index)")
    }

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: childIdentities.map {
          ResolvedNode(identity: $0, kind: .view("Child"))
        }
      )
    )

    let baseline = graph.debugTotalStateSnapshot()
    let draft = makeDraft(graph)

    updateNode(
      graph,
      identity: rootIdentity,
      kind: .root,
      children: []
    )
    draft.recordPreparedCheckpoint(from: graph)

    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult
        == .full(
          target: .baseline,
          reason: .deltaNodeBudgetExceeded
        )
    )
  }

  @Test("delta restore falls back when current graph no longer matches source checkpoint")
  func deltaRestoreFallsBackWhenCurrentGraphNoLongerMatchesSourceCheckpoint() {
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

    let draft = makeDraft(graph, diagnostics: true)

    updateNode(
      graph,
      identity: childIdentity,
      kind: .view("ChildUpdated")
    )
    draft.recordPreparedCheckpoint(from: graph)
    let prepared = graph.debugTotalStateSnapshot()

    draft.restoreBaselineState(in: graph)
    graph.queueDirty([rootIdentity])

    draft.materializePreparedState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == prepared)
    #expect(
      draft.debugLastDeltaCheckpointRestoreResult
        == .full(
          target: .prepared,
          reason: .currentCheckpointMismatch
        )
    )

    let diagnostics = draft.commitRuntimeRegistrations(from: graph)
    #expect(
      diagnostics.publication.graphCheckpointRestoreStrategy == "full_fallback"
    )
    #expect(
      diagnostics.publication.graphCheckpointRestoreFallbackReason
        == "current_checkpoint_mismatch"
    )
    #expect(diagnostics.publication.graphCheckpointDeltaRestoreCount == 1)
    #expect(diagnostics.publication.graphCheckpointFallbackRestoreCount == 1)
  }

  @Test("shadow summary records created and removed node IDs")
  func shadowSummaryRecordsCreatedAndRemovedNodeIDs() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Child")
    let insertedIdentity = testIdentity("Root", "Inserted")

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )

    let baseline = graph.debugTotalStateSnapshot()
    let childNodeID = baseline.nodeIDByIdentity[childIdentity]!
    let draft = makeDraft(graph)

    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: insertedIdentity, kind: .view("Inserted"))
        ]
      ),
      accessedStateSlots: 0
    )
    draft.recordPreparedCheckpoint(from: graph)

    let summary = draft.debugDeltaCheckpointSummary
    #expect(summary?.baselineNodeCount == 2)
    #expect(summary?.preparedNodeCount == 2)
    #expect(summary?.createdNodeIDs.count == 1)
    #expect(summary?.removedNodeIDs == [childNodeID])
    #expect(summary?.touchedNodeCount == summary?.touchedNodeIDs.count)
    #expect(summary?.createdNodeCount == summary?.createdNodeIDs.count)
    #expect(summary?.removedNodeCount == summary?.removedNodeIDs.count)

    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)
  }

  @Test("publication diagnostics include shadow delta checkpoint summary")
  func publicationDiagnosticsIncludeShadowDeltaCheckpointSummary() {
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
    let draft = makeDraft(graph, diagnostics: true)

    graph.beginFrame()
    let childNode = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      childNode,
      resolved: ResolvedNode(identity: childIdentity, kind: .view("ChildUpdated")),
      accessedStateSlots: 0
    )
    draft.recordPreparedCheckpoint(from: graph)

    let diagnostics = draft.commitRuntimeRegistrations(from: graph)
    let summary = draft.debugDeltaCheckpointSummary

    #expect(diagnostics.publication.graphCheckpointStrategy == "full_shadow_delta")
    #expect(
      diagnostics.publication.graphDeltaCheckpointNodeCount == summary?.touchedNodeCount
    )
    #expect(
      diagnostics.publication.graphDeltaCheckpointCreatedNodeCount
        == summary?.createdNodeCount
    )
    #expect(
      diagnostics.publication.graphDeltaCheckpointRemovedNodeCount
        == summary?.removedNodeCount
    )
    #expect(
      diagnostics.publication.graphDeltaCheckpointEpochDelta
        == summary?.graphMutationEpochDelta
    )
  }

  private func updateNode(
    _ graph: ViewGraph,
    identity: Identity,
    kind: NodeKind,
    children: [ResolvedNode] = []
  ) {
    graph.beginFrame()
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    _ = graph.finishEvaluation(
      node,
      resolved: ResolvedNode(
        identity: identity,
        kind: kind,
        children: children
      ),
      accessedStateSlots: 0
    )
  }

  private func makeDraft(
    _ graph: ViewGraph,
    diagnostics: Bool = true
  ) -> ViewGraphFrameDraft {
    let liveRegistrations = RuntimeRegistrationSet.scratch()
    graph.restoreCurrentFrameRuntimeRegistrations(into: liveRegistrations)
    return ViewGraphFrameDraft(
      liveRegistrations: liveRegistrations,
      checkpoint: graph.makeCheckpoint(),
      publicationDiagnosticsEnabled: diagnostics
    )
  }
}
