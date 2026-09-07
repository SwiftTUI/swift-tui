import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite
struct DeclaredChildRecompositionTests {
  @Test("requests coalesce and queue the exact live owner")
  func requestsCoalesceAndQueueOwner() throws {
    let graph = ViewGraph()
    let identity = testIdentity("DeclaredConsumer")
    _ = graph.applySnapshot(ResolvedNode(identity: identity, kind: .root))
    let owner = try #require(graph.nodeForIdentity(identity))
    var evaluations = 0
    graph.setEvaluator(for: identity) { evaluations += 1 }
    graph.beginFrame()
    graph.requestDeclaredChildRecomposition(owner: owner.ownerLifetimeID)
    graph.requestDeclaredChildRecomposition(owner: owner.ownerLifetimeID)
    let requests = graph.takeDeclaredChildRecompositionRequests()
    #expect(requests == [owner.ownerLifetimeID])
    #expect(graph.takeDeclaredChildRecompositionRequests().isEmpty)
    graph.queueDirtyEvaluationOwners(requests)
    let plan = try #require(graph.selectiveDirtyEvaluationPlan())
    #expect(plan.frontierNodeIDs == [owner.viewNodeID])
    #expect(graph.evaluateDirtyNodes(using: plan))
    #expect(evaluations == 1)
  }

  @Test("a retired consumer request cannot target its replacement at the same identity")
  func retiredConsumerDoesNotTargetReplacement() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let childIdentity = testIdentity("Root", "Consumer")
    let child = ResolvedNode(identity: childIdentity, kind: .view("Consumer"))
    let populated = ResolvedNode(identity: rootIdentity, kind: .root, children: [child])
    _ = graph.applySnapshot(populated)
    let retiredNode = try #require(graph.nodeForIdentity(childIdentity))
    let retired = retiredNode.ownerLifetimeID
    graph.requestDeclaredChildRecomposition(owner: retired)
    // Keep the request pending within this frame. applySnapshot would call
    // beginFrame and clear it before retirement, hiding a missing drain filter.
    graph.removeSubtree(rootedAt: retiredNode)
    let replacement = graph.nodeForIdentity(for: childIdentity).ownerLifetimeID
    #expect(replacement != retired)
    #expect(graph.takeDeclaredChildRecompositionRequests().isEmpty)
    graph.requestDeclaredChildRecomposition(owner: retired)
    #expect(graph.takeDeclaredChildRecompositionRequests().isEmpty)
    graph.requestDeclaredChildRecomposition(owner: replacement)
    #expect(graph.takeDeclaredChildRecompositionRequests() == [replacement])
  }

  @Test("the next frame clears discarded requests and active descent needs no replay")
  func frameAttemptClearsRequests() throws {
    let graph = ViewGraph()
    let identity = testIdentity("Consumer")
    let resolved = ResolvedNode(identity: identity, kind: .root)
    _ = graph.applySnapshot(resolved)
    let owner = try #require(graph.nodeForIdentity(identity))
    let checkpoint = graph.makeCheckpoint()
    graph.requestDeclaredChildRecomposition(owner: owner.ownerLifetimeID)
    _ = graph.restoreCheckpoint(checkpoint)
    graph.beginFrame()
    #expect(graph.takeDeclaredChildRecompositionRequests().isEmpty)
    let evaluating = graph.beginEvaluation(identity: identity, invalidator: nil)
    graph.requestDeclaredChildRecomposition(owner: evaluating.ownerLifetimeID)
    #expect(graph.takeDeclaredChildRecompositionRequests().isEmpty)
    _ = graph.finishEvaluation(evaluating, resolved: resolved, accessedStateSlots: 0)
    // Having evaluated earlier in this frame does not prove a later shape
    // change was consumed. Only an evaluation still on the stack can do that.
    graph.requestDeclaredChildRecomposition(owner: evaluating.ownerLifetimeID)
    #expect(graph.takeDeclaredChildRecompositionRequests() == [evaluating.ownerLifetimeID])
  }
}
