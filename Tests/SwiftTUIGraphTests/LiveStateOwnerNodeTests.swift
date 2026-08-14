import Testing

@testable import SwiftTUIGraph

// Callback-facing state ownership is exact-lifetime keyed. Authored Identity
// is deliberately absent: a later node at the same path is a distinct owner,
// even if raw node allocation also repeats after checkpoint rollback.
@MainActor
@Suite("ViewGraph state-owner lifetimes")
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

  @Test("a live exact handle resolves in O(1)")
  func liveExactHandleResolves() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))
    let handle = try #require(registered.stateOwnerHandle)

    #expect(graph.nodeForOwnerLifetimeID(handle.ownerLifetime) === registered)
    #expect(LiveViewGraphRegistry.node(for: handle) === registered)
  }

  @Test("a same-identity re-mint cannot capture the retired handle")
  func remintDoesNotCaptureRetiredHandle() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))
    let registeredHandle = try #require(registered.stateOwnerHandle)

    // Leave and return: teardown evicts the node, the next visit mints a
    // fresh one at the same identity.
    removeChild(from: graph)
    applyChild(to: graph)
    let reminted = try #require(graph.nodeForIdentity(childIdentity))
    #expect(reminted !== registered)
    #expect(reminted.viewNodeID != registered.viewNodeID)
    #expect(reminted.ownerLifetimeID != registered.ownerLifetimeID)
    #expect(LiveViewGraphRegistry.node(for: registeredHandle) == nil)
    #expect(LiveViewGraphRegistry.node(for: reminted.stateOwnerHandle!) === reminted)
  }

  @Test("a retired owner handle resolves nil")
  func retiredHandleResolvesNil() throws {
    let graph = makeGraph()
    let registered = try #require(graph.nodeForIdentity(childIdentity))
    let handle = try #require(registered.stateOwnerHandle)

    removeChild(from: graph)
    #expect(LiveViewGraphRegistry.node(for: handle) == nil)
  }
}
