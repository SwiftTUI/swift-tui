import Testing

@testable import SwiftTUIGraph

// 2026-07-17 gallery fuzzer campaign §5 (reuse-adoption seam): a value-only
// placeholder node — minted by `nodeForResolvedNode`'s identity fallback for
// an inline-built styling wrapper (TabView's TabBody, button chrome) and never
// evaluated or applied — has a hollow init `committed` and permanently empty
// live children. `ViewNode.snapshot()`'s stale-cache rebuild used to recurse
// into such children, serving the hollow value in place of the interior
// island (nil runtime stamp, no children) and laundering it fresh. On a
// zero-computed frame that serve became the frame product: the animation
// skip-gate trapped on the vanished stamps (pointer-lab SIGTRAP) and the
// hollowed commit tore down interior nodes out from under their lifecycle
// registrations (sheet change-handler skips).
@MainActor
@Suite("ViewNode snapshot rebuild across value-only placeholders")
struct ViewNodeSnapshotRebuildTests {
  @Test("stale-cache rebuild preserves a never-applied placeholder child's committed slice")
  func rebuildPreservesValueOnlyPlaceholderInterior() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let hostIdentity = testIdentity("Root", "Host")
    let placeholderIdentity = testIdentity("Root", "Host", "TabBody")
    let interiorIdentity = testIdentity("Root", "Host", "TabBody", "Interior")
    let siblingIdentity = testIdentity("Root", "Host", "Sibling")

    // Frame 1: the host body evaluates and returns a value-only child built
    // inline (no `resolveView`, so no node evaluation) carrying interior
    // content — the production TabBody shape. `finishEvaluation`'s child
    // mapping mints a placeholder node for it; nothing ever applies it.
    graph.beginFrame()
    let root = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let host = graph.beginEvaluation(identity: hostIdentity, invalidator: nil)
    let sibling = graph.beginEvaluation(identity: siblingIdentity, invalidator: nil)
    let siblingResolved = try #require(
      graph.finishEvaluation(
        sibling,
        resolved: ResolvedNode(identity: siblingIdentity, kind: .view("Sibling")),
        accessedStateSlots: 0
      )
    )
    let placeholderValue = ResolvedNode(
      identity: placeholderIdentity,
      kind: .view("TabBody"),
      children: [
        ResolvedNode(identity: interiorIdentity, kind: .view("Interior"))
      ]
    )
    let hostResolved = try #require(
      graph.finishEvaluation(
        host,
        resolved: ResolvedNode(
          identity: hostIdentity,
          kind: .view("Host"),
          children: [placeholderValue, siblingResolved]
        ),
        accessedStateSlots: 0
      )
    )
    _ = graph.finishEvaluation(
      root,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [hostResolved]
      ),
      accessedStateSlots: 0
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    let placeholderNode = try #require(graph.nodeForIdentity(placeholderIdentity))
    #expect(placeholderNode.children.isEmpty)

    // Frame 2: a sibling under the host re-evaluates AFTER the host's
    // apply — its apply invalidates the spine's cached snapshots without
    // re-applying the host (the pointer-lab frame-2 shape). The next
    // zero-computed serve then rebuilds through the stale spine.
    graph.beginFrame()
    let siblingReapplied = graph.beginEvaluation(
      identity: siblingIdentity,
      invalidator: nil
    )
    _ = graph.finishEvaluation(
      siblingReapplied,
      resolved: ResolvedNode(identity: siblingIdentity, kind: .view("Sibling")),
      accessedStateSlots: 0
    )
    #expect(!host.hasCachedSnapshot, "the sibling apply must stale the host's cache")

    // The rebuild must keep the parent's committed slice for the
    // never-applied placeholder instead of serving its hollow init value.
    let served = graph.snapshot()

    let servedHost = try #require(served.children.first)
    let servedPlaceholder = try #require(servedHost.children.first)
    #expect(servedPlaceholder.identity == placeholderIdentity)
    #expect(servedPlaceholder.viewNodeID == placeholderNode.viewNodeID)
    #expect(servedPlaceholder.children.count == 1)
    #expect(servedPlaceholder.children.first?.identity == interiorIdentity)
  }

  @Test("a direct stale snapshot of a never-applied node does not launder freshness")
  func directSnapshotOfNeverAppliedNodeDoesNotLaunderFreshness() throws {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let hostIdentity = testIdentity("Root", "Host")
    let placeholderIdentity = testIdentity("Root", "Host", "TabBody")

    graph.beginFrame()
    let root = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let host = graph.beginEvaluation(identity: hostIdentity, invalidator: nil)
    let hostResolved = try #require(
      graph.finishEvaluation(
        host,
        resolved: ResolvedNode(
          identity: hostIdentity,
          kind: .view("Host"),
          children: [
            ResolvedNode(identity: placeholderIdentity, kind: .view("TabBody"))
          ]
        ),
        accessedStateSlots: 0
      )
    )
    _ = graph.finishEvaluation(
      root,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [hostResolved]
      ),
      accessedStateSlots: 0
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    let placeholderNode = try #require(graph.nodeForIdentity(placeholderIdentity))
    #expect(!placeholderNode.hasCachedSnapshot)
    _ = placeholderNode.snapshot()
    // Pre-fix the rebuild set `isCommittedSnapshotFresh = true` on the
    // hollow value, opening a `canReuse` path that would serve it as a
    // retained subtree.
    #expect(!placeholderNode.hasCachedSnapshot)
  }
}
