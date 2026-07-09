import Testing

@testable import SwiftTUIGraph

/// Pins the `cache-*` reuse-denial reasons of `cachedReusableResolvedNode`
/// (F94): the namespace+owner+signature reuse cache used to decline silently
/// on all of its guard branches while its `reusableSnapshot` siblings fed the
/// `[REUSE-TRACE]` histogram — a regression on this path (the toolbar-strip
/// reuse fast path) was undiagnosable without ad hoc logging.
@MainActor
@Suite("Resolved-node reuse cache denial trace")
struct ResolvedNodeReuseCacheTraceTests {
  private func withTracingEnabled(_ body: () throws -> Void) rethrows {
    let enabled = ReuseDenialTrace.isEnabled
    defer {
      ReuseDenialTrace.isEnabled = enabled
      ReuseDenialTrace.reset()
    }
    ReuseDenialTrace.isEnabled = true
    ReuseDenialTrace.reset()
    try body()
  }

  private func query(
    _ graph: ViewGraph,
    owner: Identity,
    signature: String = "sig"
  ) -> ResolvedNode? {
    graph.cachedReusableResolvedNode(
      namespace: "test",
      owner: owner,
      signature: signature,
      environment: .init(),
      transaction: .init()
    )
  }

  @Test("a cold cache records cache-miss")
  func coldCacheRecordsMiss() {
    let graph = ViewGraph()
    graph.beginFrame()
    withTracingEnabled {
      #expect(query(graph, owner: testIdentity("Root", "Strip")) == nil)
      #expect(ReuseDenialTrace.reasonCounts["cache-miss"] == 1)
    }
  }

  @Test("a signature change records cache-stale-signature")
  func staleSignatureRecordsReason() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = testIdentity("Root", "Strip")
    graph.storeResolvedNodeReuseCache(
      namespace: "test",
      owner: owner,
      signature: "old",
      node: ResolvedNode(identity: owner, kind: .view("Strip"))
    )
    withTracingEnabled {
      #expect(query(graph, owner: owner, signature: "new") == nil)
      #expect(ReuseDenialTrace.reasonCounts["cache-stale-signature"] == 1)
    }
  }

  @Test("a departed cached node records cache-node-departed and evicts the entry")
  func departedNodeRecordsReasonAndEvicts() {
    let graph = ViewGraph()
    graph.beginFrame()
    let owner = testIdentity("Root", "Strip")
    // The cached snapshot names an identity with no live node behind it.
    graph.storeResolvedNodeReuseCache(
      namespace: "test",
      owner: owner,
      signature: "sig",
      node: ResolvedNode(identity: testIdentity("Root", "Departed"), kind: .view("Strip"))
    )
    withTracingEnabled {
      #expect(query(graph, owner: owner) == nil)
      #expect(ReuseDenialTrace.reasonCounts["cache-node-departed"] == 1)
      // The stale entry is evicted, so the next query is a plain miss.
      #expect(query(graph, owner: owner) == nil)
      #expect(ReuseDenialTrace.reasonCounts["cache-miss"] == 1)
    }
  }

  @Test("denials stay silent while tracing is disabled")
  func disabledTracingRecordsNothing() {
    let graph = ViewGraph()
    graph.beginFrame()
    let enabled = ReuseDenialTrace.isEnabled
    defer {
      ReuseDenialTrace.isEnabled = enabled
      ReuseDenialTrace.reset()
    }
    ReuseDenialTrace.isEnabled = false
    ReuseDenialTrace.reset()
    #expect(query(graph, owner: testIdentity("Root", "Strip")) == nil)
    #expect(ReuseDenialTrace.reasonCounts.isEmpty)
  }
}
