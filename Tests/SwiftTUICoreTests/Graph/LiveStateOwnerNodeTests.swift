import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

// `ViewGraph.liveStateOwnerNode(registeredOwner:identity:)` re-keys
// closure-held `@State` access across a same-identity node re-mint: the
// registration-time node wins while it is still the live occupant of its
// identity; a fresh mint at the same identity supersedes it. Without the
// re-key, `.task`/`.onAppear` closures registered before a re-mint keep
// writing the orphaned node's slots — writes whose invalidations dirty the
// fresh node, which re-resolves its unchanged slots into an empty frame,
// forever (the gallery Life-tab revisit freeze).
@MainActor
@Suite("ViewGraph.liveStateOwnerNode")
struct LiveStateOwnerNodeTests {
  private let rootIdentity = testIdentity("LiveOwnerRoot")
  private let childIdentity = testIdentity("LiveOwnerRoot", "Child")

  private func makeGraph() -> ViewGraph {
    let graph = ViewGraph()
    graph.setRootEvaluator(rootIdentity: rootIdentity) {}
    applyChild(to: graph)
    return graph
  }

  private func applyChild(to graph: ViewGraph) {
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [
          ResolvedNode(identity: childIdentity, kind: .view("Child"))
        ]
      )
    )
  }

  private func removeChild(from graph: ViewGraph) {
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: []
      )
    )
  }

  @Test("the registration-time node wins while it is the live occupant")
  func registeredOccupantWins() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))

    let resolved = graph.liveStateOwnerNode(
      registeredOwner: registered.viewNodeID,
      identity: childIdentity
    )
    #expect(resolved === registered)
  }

  @Test("a same-identity re-mint supersedes the registration-time node")
  func remintSupersedesRegisteredNode() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))

    // Leave and return: teardown evicts the node, the next visit mints a
    // fresh one at the same identity.
    removeChild(from: graph)
    applyChild(to: graph)
    let reminted = try #require(graph.nodeForIdentity(childIdentity))
    #expect(reminted !== registered)
    #expect(reminted.viewNodeID != registered.viewNodeID)

    let resolved = graph.liveStateOwnerNode(
      registeredOwner: registered.viewNodeID,
      identity: childIdentity
    )
    #expect(
      resolved === reminted,
      "closure-held state access must follow the identity to the live occupant"
    )
  }

  @Test("with no live occupant the registered node is the fallback")
  func absentIdentityFallsBackToRegisteredNode() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))

    removeChild(from: graph)

    // The identity has no live occupant and the registered node is out of the
    // index; degrade to today's behavior (nil), never to a different node.
    let resolved = graph.liveStateOwnerNode(
      registeredOwner: registered.viewNodeID,
      identity: childIdentity
    )
    #expect(resolved == nil || resolved === registered)
  }
}
