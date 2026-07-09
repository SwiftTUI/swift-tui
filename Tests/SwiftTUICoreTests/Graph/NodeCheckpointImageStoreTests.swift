import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// F29: the persistent COW node-image store behind ViewGraph.makeCheckpoint().
// Under DEBUG every makeCheckpoint call additionally runs the restore-no-op
// oracle (restoring a just-created checkpoint must not change graph state), so
// each capture in these tests is itself an end-to-end soundness check; the
// suite asserts the violation counter never moves.
@MainActor
@Suite("NodeCheckpointImageStore")
struct NodeCheckpointImageStoreTests {
  private func makeGraph() -> (
    graph: ViewGraph, rootIdentity: Identity, childIdentity: Identity
  ) {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("StoreRoot")
    let childIdentity = testIdentity("StoreRoot", "Child")
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )
    return (graph, rootIdentity, childIdentity)
  }

  /// Runs `body` with the soundness probe disabled: the DEBUG create oracle's
  /// ungated restore bumps every generation past the handed-out images, so
  /// fast-path properties (O(1) image reuse, refresh precision) are only
  /// observable with the oracle off — exactly the release unsampled-frame
  /// behavior.
  private func withProbeDisabled<T>(_ body: () throws -> T) rethrows -> T {
    let wasEnabled = SoundnessProbeConfiguration.isEnabled
    SoundnessProbeConfiguration.isEnabled = false
    defer { SoundnessProbeConfiguration.isEnabled = wasEnabled }
    return try body()
  }

  @Test("an unchanged graph hands out identical images across captures")
  func unchangedCaptureReusesImages() {
    withProbeDisabled {
      let (graph, _, _) = makeGraph()

      let first = graph.makeCheckpoint()
      let second = graph.makeCheckpoint()

      #expect(Set(first.nodeCheckpoints.keys) == Set(second.nodeCheckpoints.keys))
      #expect(
        first.nodeCheckpoints.mapValues(\.checkpointMutationGeneration)
          == second.nodeCheckpoints.mapValues(\.checkpointMutationGeneration)
      )
    }
  }

  @Test("a node-local mutation refreshes exactly that node's image")
  func mutationRefreshesOnlyTheMutatedImage() throws {
    try withProbeDisabled {
      let (graph, rootIdentity, childIdentity) = makeGraph()

      let first = graph.makeCheckpoint()
      let rootID = try #require(first.index.nodeIDByIdentity[rootIdentity])
      let childID = try #require(first.index.nodeIDByIdentity[childIdentity])
      let childNode = try #require(first.index.nodesByNodeID[childID])

      // A node-local observed write (no upward invalidation walk): the child's
      // generation moves, the root's does not.
      childNode.setLifecycleState(.alive)
      let second = graph.makeCheckpoint()

      #expect(
        second.nodeCheckpoints[childID]!.checkpointMutationGeneration
          > first.nodeCheckpoints[childID]!.checkpointMutationGeneration
      )
      #expect(
        second.nodeCheckpoints[rootID]!.checkpointMutationGeneration
          == first.nodeCheckpoints[rootID]!.checkpointMutationGeneration
      )
    }
  }

  @Test("image membership tracks the live node set across structural change")
  func membershipTracksLiveNodes() throws {
    let violationsBefore = SoundnessProbeConfiguration.checkpointStoreViolationCount
    let (graph, rootIdentity, childIdentity) = makeGraph()
    _ = graph.makeCheckpoint()

    let insertedIdentity = testIdentity("StoreRoot", "Inserted")
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child")),
          ResolvedNode(identity: insertedIdentity, kind: .view("Inserted")),
        ]
      )
    )
    let grown = graph.makeCheckpoint()
    #expect(Set(grown.nodeCheckpoints.keys) == Set(grown.index.nodesByNodeID.keys))
    let insertedID = try #require(grown.index.nodeIDByIdentity[insertedIdentity])
    #expect(grown.nodeCheckpoints[insertedID] != nil)

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )
    let shrunk = graph.makeCheckpoint()
    #expect(Set(shrunk.nodeCheckpoints.keys) == Set(shrunk.index.nodesByNodeID.keys))
    #expect(SoundnessProbeConfiguration.checkpointStoreViolationCount == violationsBefore)
  }

  @Test("captures after a rollback restore stay coherent (store adoption)")
  func captureAfterRestoreStaysCoherent() {
    let violationsBefore = SoundnessProbeConfiguration.checkpointStoreViolationCount
    let (graph, rootIdentity, childIdentity) = makeGraph()

    let baseline = graph.makeCheckpoint()
    let before = graph.debugTotalStateSnapshot()

    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("ChildUpdated")),
          ResolvedNode(
            identity: testIdentity("StoreRoot", "Inserted"),
            kind: .view("Inserted")
          ),
        ]
      )
    )
    graph.invalidateAndQueueDirty([childIdentity])
    #expect(graph.debugTotalStateSnapshot() != before)

    graph.restoreCheckpoint(baseline)
    #expect(graph.debugTotalStateSnapshot() == before)

    // The post-restore capture rides the adopted store; under DEBUG its
    // restore-no-op oracle re-verifies the whole store end to end.
    let recaptured = graph.makeCheckpoint()
    #expect(
      Set(recaptured.nodeCheckpoints.keys) == Set(recaptured.index.nodesByNodeID.keys)
    )
    #expect(graph.debugTotalStateSnapshot() == before)
    #expect(SoundnessProbeConfiguration.checkpointStoreViolationCount == violationsBefore)
  }

  @Test("checkpoint-store violations are counted with detail")
  func violationCounterPlumbing() {
    let countBefore = SoundnessProbeConfiguration.checkpointStoreViolationCount
    let detailBefore = SoundnessProbeConfiguration.lastViolationDetail
    defer {
      SoundnessProbeConfiguration.checkpointStoreViolationCount = countBefore
      SoundnessProbeConfiguration.lastViolationDetail = detailBefore
    }

    SoundnessProbeConfiguration.recordCheckpointStoreViolation("store test detail")

    #expect(SoundnessProbeConfiguration.checkpointStoreViolationCount == countBefore + 1)
    #expect(SoundnessProbeConfiguration.lastViolationDetail == "store test detail")
  }
}
