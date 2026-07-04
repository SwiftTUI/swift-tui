import Testing

@testable import SwiftTUICore

// F29 slice 3: checkpoint restores are generation-gated (only nodes whose live
// generation differs from the image are rewritten) — the successor of the
// Stage-2B guarded delta restore, without the shadow tracker, restore plans,
// budget heuristic, or fallback reasons. These tests carry forward the shadow
// suite's behavioral scenarios: exact baseline/prepared round-trips, precision
// (untouched nodes are skipped), created/removed membership, materialize ↔
// suspend cycles with a preserved dirty overlay, near-full changes, and an
// intervening mutation between suspend and materialize. Under DEBUG every
// restore additionally runs the gated-vs-ungated oracle and every capture the
// restore-no-op oracle.
@MainActor
@Suite("ViewGraph gen-gated checkpoint restore")
struct ViewGraphCheckpointRestoreTests {
  @Test("restore lands exactly on baseline and reports the restored count")
  func restoreLandsOnBaseline() throws {
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

    #expect(graph.debugTotalStateSnapshot() != baseline)
    draft.restoreBaselineState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == baseline)

    // Skip precision is NOT observable here under DEBUG: the create oracle's
    // ungated restore inside every makeCheckpoint bumps all live generations
    // past the handed-out images' capture metadata, so gated restores rewrite
    // everything on oracle-verified captures (release unsampled frames skip
    // precisely — see `gatingSkipsGenerationMatchedNodes` for the primitive).
    let restored = try #require(draft.debugLastRestoreRestoredNodeCount)
    #expect(restored >= 1 && restored <= 3)
  }

  @Test("the gating primitive skips generation-matched nodes and counts rewrites")
  func gatingSkipsGenerationMatchedNodes() {
    let idA = ViewNodeID(rawValue: 1)
    let idB = ViewNodeID(rawValue: 2)
    let nodeA = ViewNode(viewNodeID: idA, identity: testIdentity("A"))
    let nodeB = ViewNode(viewNodeID: idB, identity: testIdentity("B"))
    let nodes = [idA: nodeA, idB: nodeB]

    let images = ViewGraphNodeCheckpointing.makeNodeCheckpoints(nodes)

    // Untouched since capture: both skipped.
    #expect(
      ViewGraphNodeCheckpointing.restoreNodeCheckpoints(images, nodesByNodeID: nodes) == 0
    )
    #expect(nodeB.isDirty == true)

    // Mutate one node past its image (markDirty is fresh-node-idempotent on
    // state but still bumps the generation through the observer).
    nodeB.markDirty()
    #expect(
      ViewGraphNodeCheckpointing.restoreNodeCheckpoints(images, nodesByNodeID: nodes) == 1
    )
    // The rewrite itself bumps the generation (restores never rewind), so a
    // second pass restores the same node again rather than aliasing.
    #expect(
      ViewGraphNodeCheckpointing.restoreNodeCheckpoints(images, nodesByNodeID: nodes) == 1
    )
    // The ungated ground truth rewrites unconditionally.
    ViewGraphNodeCheckpointing.restoreNodeCheckpointsUngated(images, nodesByNodeID: nodes)
    #expect(nodeA.isDirty == true && nodeB.isDirty == true)
  }

  @Test("gen-gated restore round-trips baseline and prepared state")
  func restoreRoundTripsBaselineAndPreparedState() {
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

    draft.materializePreparedState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == prepared)
  }

  @Test("gen-gated restore round-trips created and removed node state")
  func restoreRoundTripsCreatedAndRemovedNodeState() {
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

    draft.materializePreparedState(in: graph)
    #expect(graph.debugTotalStateSnapshot() == prepared)
  }

  @Test("gen-gated restore survives materialize suspend cycles with preserved dirty overlay")
  func restoreSurvivesMaterializeSuspendCyclesWithPreservedDirtyOverlay() {
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

    draft.materializePreparedState(
      in: graph,
      preservingCurrentStateMutations: true
    )
    #expect(
      graph.debugTotalStateSnapshot().graphLocalDirtyIdentities.contains(
        siblingIdentity
      )
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

    draft.materializePreparedState(
      in: graph,
      preservingCurrentStateMutations: true
    )
    #expect(
      graph.debugTotalStateSnapshot().graphLocalDirtyIdentities.contains(
        siblingIdentity
      )
    )
  }

  @Test("near-full structural change restores exactly (no budget heuristic)")
  func nearFullChangeRestoresExactly() {
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
  }

  @Test("a mutation between suspend and materialize still lands exactly on prepared")
  func interveningMutationStillLandsOnPrepared() {
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

    let diagnostics = draft.commitRuntimeRegistrations(from: graph)
    #expect(diagnostics.publication.graphCheckpointRestoreStrategy == "gen_gated")
    #expect(diagnostics.publication.graphCheckpointRestoreFallbackReason == nil)
    #expect(diagnostics.publication.graphCheckpointDeltaRestoreCount == 2)
    #expect(diagnostics.publication.graphCheckpointFallbackRestoreCount == 0)
  }

  @Test("publication diagnostics carry the gen-gated strategy and restored count")
  func publicationDiagnosticsCarryGenGatedRestoreCounts() {
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
    draft.restoreBaselineState(in: graph)

    let diagnostics = draft.commitRuntimeRegistrations(from: graph)
    #expect(diagnostics.publication.graphCheckpointStrategy == "gen_gated_store")
    #expect(diagnostics.publication.graphCheckpointRestoreStrategy == "gen_gated")
    #expect(
      diagnostics.publication.graphDeltaCheckpointNodeCount
        == draft.debugLastRestoreRestoredNodeCount
    )
    #expect(diagnostics.publication.graphCheckpointDeltaRestoreCount == 1)
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
