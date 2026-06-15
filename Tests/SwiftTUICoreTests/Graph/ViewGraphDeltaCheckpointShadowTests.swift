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
