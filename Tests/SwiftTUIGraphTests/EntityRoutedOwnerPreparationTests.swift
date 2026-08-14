import Foundation
import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Entity-routed owner preparation", .serialized)
struct EntityRoutedOwnerPreparationTests {
  @Test("same authored identity keeps distinct routed owners and slot tables")
  func coResidentOwnersRemainDistinctAndAdoptInFrame() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("CoResidentRestore")
    let sharedIdentity = testIdentity("CoResidentRestore", "Shared")
    let entityA = EntityIdentity("A")
    let entityB = EntityIdentity("B")

    graph.beginFrame()
    let preparedA = graph.prepareEntityRoutedOwnerPreservingCoResidentIdentity(
      identity: sharedIdentity,
      entityIdentity: entityA
    )
    preparedA.restoreStateSlot(
      StateSlotIdentifier(ordinal: 0),
      slot: AnyStateSlot(41)
    )
    let preparedB = graph.prepareEntityRoutedOwnerPreservingCoResidentIdentity(
      identity: sharedIdentity,
      entityIdentity: entityB
    )
    preparedB.restoreStateSlot(
      StateSlotIdentifier(ordinal: 0),
      slot: AnyStateSlot("forty-two")
    )

    #expect(preparedA !== preparedB)
    #expect(preparedA.viewNodeID != preparedB.viewNodeID)
    #expect(preparedA.ownerLifetimeID != preparedB.ownerLifetimeID)
    #expect(preparedA.identity == sharedIdentity)
    #expect(preparedB.identity == sharedIdentity)
    #expect(graph.nodeForIdentity(sharedIdentity) === preparedA)
    #expect(graph.nodeForEntityIdentity(entityA) === preparedA)
    #expect(graph.nodeForEntityIdentity(entityB) === preparedB)

    let adoptedA = graph.beginEvaluation(
      identity: sharedIdentity,
      entityIdentity: entityA,
      invalidator: nil
    )
    #expect(adoptedA === preparedA)
    #expect(adoptedA.primedStateSlot(ordinal: 0, seed: -1) == 41)
    let resolvedA = try #require(
      graph.finishEvaluation(
        adoptedA,
        resolved: entityResolvedNode(
          identity: sharedIdentity,
          kind: .view("A"),
          entity: entityA
        ),
        accessedStateSlots: 1
      )
    )

    let adoptedB = graph.beginEvaluation(
      identity: sharedIdentity,
      entityIdentity: entityB,
      invalidator: nil
    )
    #expect(adoptedB === preparedB)
    #expect(adoptedB.primedStateSlot(ordinal: 0, seed: "seed") == "forty-two")
    let resolvedB = try #require(
      graph.finishEvaluation(
        adoptedB,
        resolved: entityResolvedNode(
          identity: sharedIdentity,
          kind: .view("B"),
          entity: entityB
        ),
        accessedStateSlots: 1
      )
    )

    let root = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let resolvedRoot = try #require(
      graph.finishEvaluation(
        root,
        resolved: ResolvedNode(
          identity: rootIdentity,
          kind: .root,
          children: [resolvedA, resolvedB]
        ),
        accessedStateSlots: 0
      )
    )
    _ = graph.finalizeFrame(resolved: resolvedRoot, placed: nil)

    #expect(graph.nodeForViewNodeID(preparedA.viewNodeID) === preparedA)
    #expect(graph.nodeForViewNodeID(preparedB.viewNodeID) === preparedB)
    #expect(preparedA.identity == sharedIdentity)
    #expect(preparedB.identity == sharedIdentity)
    #expect(graph.nodeForEntityIdentity(entityA) === preparedA)
    #expect(graph.nodeForEntityIdentity(entityB) === preparedB)
  }

  @Test("an unadopted routed owner is reclaimed at the frame barrier")
  func unadoptedOwnerIsReclaimed() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("UnadoptedRestore")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))
    let committedRoot = graph.snapshot(rootIdentity: rootIdentity)

    graph.beginFrame()
    let staged = graph.prepareEntityRoutedOwnerPreservingCoResidentIdentity(
      identity: testIdentity("UnadoptedRestore", "Missing"),
      entityIdentity: EntityIdentity("missing")
    )
    graph.recordReusedSubtree(committedRoot, invalidator: nil)
    _ = graph.finalizeFrame(resolved: committedRoot, placed: nil)

    #expect(graph.nodeForViewNodeID(staged.viewNodeID) == nil)
    #expect(graph.nodeForEntityIdentity(EntityIdentity("missing")) == nil)
  }

  @Test("checkpoint restore clears co-resident membership and stale ABA routes")
  func checkpointRestoreIsABASafe() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("CoResidentCheckpoint")
    _ = graph.applySnapshot(ResolvedNode(identity: rootIdentity, kind: .root))
    let baseline = graph.makeCheckpoint()
    let sharedIdentity = testIdentity("CoResidentCheckpoint", "Shared")
    let firstEntity = EntityIdentity("first")

    graph.beginFrame()
    let first = graph.prepareEntityRoutedOwnerPreservingCoResidentIdentity(
      identity: sharedIdentity,
      entityIdentity: firstEntity
    )
    let firstNodeID = first.viewNodeID
    let firstOwnerLifetimeID = first.ownerLifetimeID
    graph.restoreCheckpoint(baseline)

    #expect(graph.nodeForViewNodeID(firstNodeID) == nil)
    #expect(graph.nodeForOwnerLifetimeID(firstOwnerLifetimeID) == nil)
    #expect(graph.nodeForEntityIdentity(firstEntity) == nil)

    let successorEntity = EntityIdentity("successor")
    graph.beginFrame()
    let successor = graph.prepareEntityRoutedOwnerPreservingCoResidentIdentity(
      identity: sharedIdentity,
      entityIdentity: successorEntity
    )
    // Graph checkpoints restore the allocator by value, so this may reuse the
    // raw node ID. The entity route must nevertheless describe only the
    // restored generation, never the discarded candidate.
    #expect(successor.viewNodeID == firstNodeID)
    #expect(successor.ownerLifetimeID != firstOwnerLifetimeID)
    #expect(graph.nodeForEntityIdentity(firstEntity) == nil)
    #expect(graph.nodeForEntityIdentity(successorEntity) === successor)
    #expect(graph.nodeForOwnerLifetimeID(successor.ownerLifetimeID) === successor)

    // A late teardown of the discarded candidate has the same raw node ID,
    // but cannot remove the current token-index occupant.
    graph.removeSubtree(rootedAt: first)
    #expect(graph.nodeForViewNodeID(successor.viewNodeID) === successor)
    #expect(graph.nodeForOwnerLifetimeID(successor.ownerLifetimeID) === successor)

    graph.restoreCheckpoint(baseline)
    #expect(graph.nodeForViewNodeID(successor.viewNodeID) == nil)
    #expect(graph.nodeForOwnerLifetimeID(successor.ownerLifetimeID) == nil)
    #expect(graph.nodeForEntityIdentity(successorEntity) == nil)
  }

  @Test("preparation preserves the fatal state-slot mismatch contract")
  func stateSlotMismatchContractRemainsFatal() throws {
    let nodeSource = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewNode.swift"
    )
    let routingSource = try SourceParsingTestSupport.sourceText(
      relativePath: "Sources/SwiftTUIGraph/Resolve/ViewGraphEntityRouting.swift"
    )
    let preparationBody = try #require(
      routingSource
        .components(
          separatedBy: "package func prepareEntityRoutedOwnerPreservingCoResidentIdentity"
        )
        .dropFirst()
        .first?
        .components(separatedBy: "func flattenedStateOwnerNode")
        .first
    )

    #expect(nodeSource.contains("State slot type mismatch on node"))
    #expect(!preparationBody.contains("resetStateSlots"))
  }
}

@MainActor
private func entityResolvedNode(
  identity: Identity,
  kind: NodeKind,
  entity: EntityIdentity
) -> ResolvedNode {
  var resolved = ResolvedNode(identity: identity, kind: kind)
  resolved.attachingEntityIdentity(entity, at: resolved.structuralPath)
  return resolved
}
