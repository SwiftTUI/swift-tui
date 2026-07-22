import Testing

@testable import SwiftTUICore
@testable import SwiftTUIViews

/// The retained-reuse gate's stack-lean arm (bounded-depth-reuse program):
/// `!stackLeanResolveProfile || leanRetainedReuse`. One environment-adaptive
/// test covers all three repo-gate lanes — the default lane (non-lean:
/// retained reuse fires), the stack-lean lane (reuse denied: the deployed
/// WebKit shape), and the stack-lean + retained-reuse lane (reuse fires
/// again). The observable is the sibling's body re-evaluation count on a
/// frame whose invalidation names only the other subtree.
@MainActor
struct LeanRetainedReuseGateTests {
  private final class BodyCounter {
    private(set) var count = 0
    func increment() { count += 1 }
  }

  private struct CountingLeaf: View {
    let counter: BodyCounter
    let label: String

    var body: some View {
      counter.increment()
      return Text(label)
    }
  }

  private func makeContext(
    _ graph: ViewGraph,
    identity: Identity,
    invalidatedIdentities: Set<Identity> = []
  ) -> ResolveContext {
    var context = ResolveContext(
      identity: identity,
      environmentValues: .init(),
      invalidatedIdentities: invalidatedIdentities,
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return context
  }

  @Test("a disjoint sibling reuses exactly when the profile's gate allows it")
  func disjointSiblingReuseFollowsProfileGate() {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let invalidatedCounter = BodyCounter()
    let disjointCounter = BodyCounter()

    let view = VStack {
      CountingLeaf(counter: invalidatedCounter, label: "invalidated")
      CountingLeaf(counter: disjointCounter, label: "disjoint")
    }

    graph.beginFrame()
    _ = Resolver().resolve(view, in: makeContext(graph, identity: rootIdentity))
    let firstFrame = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(resolved: firstFrame, placed: nil)
    #expect(invalidatedCounter.count == 1)
    #expect(disjointCounter.count == 1)

    // The first counting leaf's resolved identity (document order) is the
    // invalidation target — derived from the committed tree, so the test
    // stays honest against lowering/identity-path changes. The custom
    // wrapper chain-collapses into its body's `Text` node, so the leaves
    // surface as the two `Text` kinds.
    var leafIdentities: [Identity] = []
    var work: [ResolvedNode] = [firstFrame]
    while let current = work.popLast() {
      if current.kind == .view("Text") {
        leafIdentities.append(current.identity)
      }
      work.append(contentsOf: current.children.reversed())
    }
    #expect(leafIdentities.count == 2)
    guard let invalidatedIdentity = leafIdentities.first else {
      return
    }

    graph.beginFrame()
    _ = Resolver().resolve(
      view,
      in: makeContext(
        graph,
        identity: rootIdentity,
        invalidatedIdentities: [invalidatedIdentity]
      )
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    // The invalidated leaf always recomputes.
    #expect(invalidatedCounter.count == 2)

    let retainedReuseActive = !stackLeanResolveProfile || leanRetainedReuse
    if retainedReuseActive {
      #expect(
        disjointCounter.count == 1,
        "the disjoint sibling should have been served from retained reuse"
      )
    } else {
      #expect(
        disjointCounter.count == 2,
        "the stack-lean profile without the opt-in must recompute everything"
      )
    }
  }
}
