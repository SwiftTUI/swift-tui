import Testing

@testable import SwiftTUICore

// Direct unit coverage for the two stateless reconciliation operators carved off
// ViewGraph during the #10 decomposition. ViewGraph's forwarders are `private`,
// so prior coverage of these was only indirect (through full-graph applies and
// the checkpoint-totality guard). These tests drive the operators on
// hand-built field groups so each pure-read contract is pinned on its own.

@MainActor
@Suite("GraphNodeIndexQuery stateless lookups")
struct GraphNodeIndexQueryTests {
  private struct Fixture {
    var index: ViewGraph.GraphIndex
    var idA: ViewNodeID
    var idB: ViewNodeID
    var identityA: Identity
    var identityB: Identity
    var nodeA: ViewNode
    var nodeB: ViewNode
  }

  private func makeFixture() -> Fixture {
    let idA = ViewNodeID(rawValue: 1)
    let idB = ViewNodeID(rawValue: 2)
    let identityA = testIdentity("Root", "A")
    let identityB = testIdentity("Root", "B")
    let nodeA = ViewNode(viewNodeID: idA, identity: identityA)
    let nodeB = ViewNode(viewNodeID: idB, identity: identityB)

    var index = ViewGraph.GraphIndex()
    index.nodesByNodeID = [idA: nodeA, idB: nodeB]
    index.nodeIDByIdentity = [identityA: idA, identityB: idB]
    index.identityByNodeID = [idA: identityA, idB: identityB]

    return Fixture(
      index: index,
      idA: idA,
      idB: idB,
      identityA: identityA,
      identityB: identityB,
      nodeA: nodeA,
      nodeB: nodeB
    )
  }

  @Test("node(for:identity) resolves a present identity and nils an absent one")
  func nodeForIdentity() {
    let fixture = makeFixture()
    #expect(GraphNodeIndexQuery.node(for: fixture.identityA, in: fixture.index) === fixture.nodeA)
    #expect(
      GraphNodeIndexQuery.node(for: testIdentity("Root", "Absent"), in: fixture.index) == nil
    )
  }

  @Test("node(for:viewNodeID) resolves a present id and nils an absent one")
  func nodeForViewNodeID() {
    let fixture = makeFixture()
    #expect(GraphNodeIndexQuery.node(for: fixture.idB, in: fixture.index) === fixture.nodeB)
    #expect(GraphNodeIndexQuery.node(for: ViewNodeID(rawValue: 999), in: fixture.index) == nil)
  }

  @Test("viewNodeID(for:identity) maps a present identity to its id")
  func viewNodeIDForIdentity() {
    let fixture = makeFixture()
    #expect(
      GraphNodeIndexQuery.viewNodeID(for: fixture.identityA, in: fixture.index) == fixture.idA)
    #expect(
      GraphNodeIndexQuery.viewNodeID(for: testIdentity("Root", "Absent"), in: fixture.index) == nil
    )
  }

  @Test("identities(for:viewNodeIDs) maps ids to identities and drops unmapped ids")
  func identitiesForViewNodeIDs() {
    let fixture = makeFixture()
    #expect(
      GraphNodeIndexQuery.identities(for: [fixture.idA, fixture.idB], in: fixture.index)
        == Set([fixture.identityA, fixture.identityB])
    )
    // An id with no identity mapping contributes nothing.
    #expect(
      GraphNodeIndexQuery.identities(
        for: [fixture.idA, ViewNodeID(rawValue: 999)], in: fixture.index)
        == Set([fixture.identityA])
    )
  }

  @Test("nodeIDs(for:identities) maps identities to ids and drops unmapped identities")
  func nodeIDsForIdentities() {
    let fixture = makeFixture()
    #expect(
      GraphNodeIndexQuery.nodeIDs(for: [fixture.identityA, fixture.identityB], in: fixture.index)
        == Set([fixture.idA, fixture.idB])
    )
    #expect(
      GraphNodeIndexQuery.nodeIDs(
        for: [fixture.identityA, testIdentity("Root", "Absent")],
        in: fixture.index
      ) == Set([fixture.idA])
    )
  }

  @Test("nodeIDs(forResolvedNode) unions the structural-path set with the node's own stamp")
  func nodeIDsForResolvedNode() {
    var fixture = makeFixture()
    let resolved = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 3),
      identity: testIdentity("Root", "C"),
      kind: .view("C")
    )
    fixture.index.nodeIDsByStructuralPath = [resolved.structuralPath: [fixture.idA, fixture.idB]]

    // The structural path's set, unioned with the resolved node's own stamp.
    #expect(
      GraphNodeIndexQuery.nodeIDs(forResolvedNode: resolved, in: fixture.index)
        == Set([fixture.idA, fixture.idB, ViewNodeID(rawValue: 3)])
    )

    // An unstamped node whose path is absent from the index yields the empty set.
    let unstamped = ResolvedNode(
      identity: testIdentity("Root", "Unindexed"),
      kind: .view("Unindexed")
    )
    #expect(
      GraphNodeIndexQuery.nodeIDs(forResolvedNode: unstamped, in: ViewGraph.GraphIndex()).isEmpty
    )
  }
}

@MainActor
@Suite("GraphCheckpointStore snapshot + mutation-state operators")
struct GraphCheckpointStoreTests {
  @Test("makeCheckpoint routes every field group into its matching checkpoint slot")
  func makeCheckpointMirrorsGroups() {
    let rootID = ViewNodeID(rawValue: 1)
    let rootIdentity = testIdentity("Root")
    let root = ViewNode(viewNodeID: rootID, identity: rootIdentity)

    var index = ViewGraph.GraphIndex()
    index.nodesByNodeID = [rootID: root]
    index.nodeIDByIdentity = [rootIdentity: rootID]

    var rootEvaluation = ViewGraph.RootEvaluation()
    rootEvaluation.evaluationRootIdentity = rootIdentity

    var dirtyState = ViewGraph.DirtyState()
    dirtyState.requiresRootEvaluation = true
    dirtyState.invalidatedNodeIDs = [rootID]

    var taskDescriptors = ViewGraph.TaskDescriptorState()
    taskDescriptors.nextTaskDescriptorIdentityToken = 77

    var frameCommit = ViewGraph.FrameCommitState()
    frameCommit.currentFrameID = 42
    frameCommit.checkpointMutationEpoch = 7

    let checkpoint = GraphCheckpointStore.makeCheckpoint(
      root: root,
      index: index,
      rootEvaluation: rootEvaluation,
      viewportLifecycle: ViewGraph.ViewportLifecycleState(),
      eventBuffers: ViewGraph.LifecycleEventBuffers(),
      dirtyState: dirtyState,
      lifecycleEvaluation: ViewGraph.LifecycleEvaluationOwnership(),
      taskDescriptors: taskDescriptors,
      dependencyIndex: ViewGraph.DependencyIndex(),
      frameCommit: frameCommit,
      nodesByNodeID: index.nodesByNodeID
    )

    // Sentinels spread across the parameter list catch any slot transposition.
    #expect(checkpoint.root === root)
    #expect(checkpoint.index.nodeIDByIdentity[rootIdentity] == rootID)
    #expect(checkpoint.rootEvaluation.evaluationRootIdentity == rootIdentity)
    #expect(checkpoint.dirtyState.requiresRootEvaluation)
    #expect(checkpoint.dirtyState.invalidatedNodeIDs == [rootID])
    #expect(checkpoint.taskDescriptors.nextTaskDescriptorIdentityToken == 77)
    #expect(checkpoint.frameCommit.currentFrameID == 42)
    #expect(checkpoint.frameCommit.checkpointMutationEpoch == 7)
    // One node checkpoint is produced per live node.
    #expect(Set(checkpoint.nodeCheckpoints.keys) == Set([rootID]))
  }

  @Test("checkpointMutationStateSnapshot captures the epoch and per-node generations")
  func mutationStateSnapshot() {
    let idA = ViewNodeID(rawValue: 1)
    let idB = ViewNodeID(rawValue: 2)
    let nodeA = ViewNode(viewNodeID: idA, identity: testIdentity("A"))
    let nodeB = ViewNode(viewNodeID: idB, identity: testIdentity("B"))
    nodeB.recordCheckpointMutation()
    nodeB.recordCheckpointMutation()

    let state = GraphCheckpointStore.checkpointMutationStateSnapshot(
      epoch: 5,
      nodesByNodeID: [idA: nodeA, idB: nodeB]
    )

    #expect(state.checkpointMutationEpoch == 5)
    #expect(state.nodeMutationGenerations == [idA: 0, idB: 2])
  }

  @Test("checkpointMutationStateMatches holds only when epoch, keys, and generations all agree")
  func mutationStateMatches() {
    let idA = ViewNodeID(rawValue: 1)
    let idB = ViewNodeID(rawValue: 2)
    let nodeA = ViewNode(viewNodeID: idA, identity: testIdentity("A"))
    let nodeB = ViewNode(viewNodeID: idB, identity: testIdentity("B"))
    let nodes = [idA: nodeA, idB: nodeB]

    let state = GraphCheckpointStore.checkpointMutationStateSnapshot(
      epoch: 5,
      nodesByNodeID: nodes
    )

    // Identical epoch + key set + generations → match.
    #expect(
      GraphCheckpointStore.checkpointMutationStateMatches(
        epoch: 5,
        nodesByNodeID: nodes,
        against: state
      )
    )
    // A different epoch breaks the match even when nodes are untouched.
    #expect(
      !GraphCheckpointStore.checkpointMutationStateMatches(
        epoch: 6,
        nodesByNodeID: nodes,
        against: state
      )
    )
    // A changed key set breaks the match.
    #expect(
      !GraphCheckpointStore.checkpointMutationStateMatches(
        epoch: 5,
        nodesByNodeID: [idA: nodeA],
        against: state
      )
    )
    // A bumped per-node generation breaks the match.
    nodeB.recordCheckpointMutation()
    #expect(
      !GraphCheckpointStore.checkpointMutationStateMatches(
        epoch: 5,
        nodesByNodeID: nodes,
        against: state
      )
    )
  }
}
