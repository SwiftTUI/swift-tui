import Testing

@testable import SwiftTUIGraph

@MainActor
@Suite("Resolve lifetime scope")
struct ResolveLifetimeScopeTests {
  @Test("a committed child needs no detached-hosted anchor")
  func committedChildNeedsNoHostedAnchor() throws {
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let child = evaluateStoredNode(graph, named: "Child")
    graph.lifetimeAnchors.insert(
      anchor: .committedValue(host.viewNodeID),
      for: child.viewNodeID
    )

    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(child)
    }

    #expect(
      !graph.lifetimeAnchors.anchors(for: child.viewNodeID)
        .contains(.hostedDetached(host.viewNodeID))
    )
  }

  @Test("a detached result follows its nearest nested host")
  func detachedResultFollowsNearestNestedHost() throws {
    let graph = ViewGraph()
    let outer = evaluateStoredNode(graph, named: "Outer")
    let inner = evaluateStoredNode(graph, named: "Inner")
    let leaf = evaluateStoredNode(graph, named: "Leaf")

    graph.withResolveLifetimeScope(hostedBy: outer) {
      graph.reportResolvedLifetimeNode(inner)
      graph.withResolveLifetimeScope(hostedBy: inner) {
        graph.reportResolvedLifetimeNode(leaf)
      }
    }

    #expect(
      graph.lifetimeAnchors.anchors(for: inner.viewNodeID)
        .contains(.hostedDetached(outer.viewNodeID))
    )
    #expect(
      graph.lifetimeAnchors.anchors(for: leaf.viewNodeID)
        .contains(.hostedDetached(inner.viewNodeID))
    )
    #expect(
      !graph.lifetimeAnchors.anchors(for: leaf.viewNodeID)
        .contains(.hostedDetached(outer.viewNodeID))
    )
  }

  @Test("navigation ownership avoids a redundant hosted anchor")
  func durableOwnershipAvoidsRedundantHosting() throws {
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let navigationOwned = evaluateStoredNode(graph, named: "Navigation")
    graph.lifetimeAnchors.insert(
      anchor: .navigationSurface(host.viewNodeID),
      for: navigationOwned.viewNodeID
    )

    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(navigationOwned)
    }

    #expect(
      !graph.lifetimeAnchors.anchors(for: navigationOwned.viewNodeID)
        .contains(.hostedDetached(host.viewNodeID))
    )
  }

  @Test("an entity home is not a durable owner — the node still takes a hosted anchor (F91)")
  func entityHomeIsNotADurableOwner() throws {
    // An entity route is not a lifetime root. The reachability census refuses
    // to seed entity homes (`LifetimeRelationCensus`), and the frame barrier
    // withdraws the route as soon as the entity goes inactive or its home
    // leaves the live set (`releaseInactiveEntityRoutes`). Treating it as
    // durable here left a dropped `ForEach`/`List` element — which always
    // carries one — with that route as its ONLY claim, so the barrier stripped
    // it and stranded the node anchorless and unreachable for the rest of the
    // graph's life. That was the whole measured `teardown-coherence-leak`
    // population's strand root.
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let entityOwned = evaluateStoredNode(graph, named: "Entity")
    graph.lifetimeAnchors.insert(
      anchor: .entityHome(EntityIdentity("row")),
      for: entityOwned.viewNodeID
    )

    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(entityOwned)
    }

    #expect(
      graph.lifetimeAnchors.anchors(for: entityOwned.viewNodeID)
        .contains(.hostedDetached(host.viewNodeID))
    )
    // Releasing the entity route must now leave the node owned, not stranded.
    graph.lifetimeAnchors.removeEntityHome(for: entityOwned.viewNodeID)
    #expect(
      graph.lifetimeAnchors.anchors(for: entityOwned.viewNodeID)
        == [.hostedDetached(host.viewNodeID)]
    )
  }

  @Test("re-observing a detached result refreshes its declaration without duplicating its edge")
  func warmObservationRefreshesDeclaration() throws {
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let detached = evaluateStoredNode(graph, named: "Detached")
    let countBefore = SoundnessProbeConfiguration.automaticLifetimeAnchorCount

    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(detached)
    }
    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(detached)
    }

    #expect(
      graph.lifetimeAnchors.anchors(for: detached.viewNodeID)
        == [.hostedDetached(host.viewNodeID)]
    )
    #expect(SoundnessProbeConfiguration.automaticLifetimeAnchorCount == countBefore + 2)
  }

  @Test("removing a host cascades through an automatically classified root")
  func hostRemovalCascadesThroughAutomaticRoot() throws {
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let detached = evaluateStoredNode(graph, named: "Detached")
    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(detached)
    }

    graph.beginFrame()
    graph.removeSubtree(rootedAt: host)

    #expect(graph.nodeForViewNodeID(host.viewNodeID) == nil)
    #expect(graph.nodeForViewNodeID(detached.viewNodeID) == nil)
    #expect(graph.lifetimeAnchors.isInverseConsistent)
  }

  @Test("a captured scope uses a live host and ignores a dead one")
  func capturedScopeRequiresLiveHost() throws {
    let graph = ViewGraph()
    let liveHost = evaluateStoredNode(graph, named: "LiveHost")
    let liveDetached = evaluateStoredNode(graph, named: "LiveDetached")
    graph.withCapturedResolveLifetimeScope(hostedBy: liveHost) {
      #expect(ViewNodeContext.current === liveHost)
      graph.reportResolvedLifetimeNode(liveDetached)
    }
    #expect(
      graph.lifetimeAnchors.anchors(for: liveDetached.viewNodeID)
        .contains(.hostedDetached(liveHost.viewNodeID))
    )

    let deadHost = evaluateStoredNode(graph, named: "DeadHost")
    let detachedAfterDeath = evaluateStoredNode(graph, named: "DetachedAfterDeath")
    graph.beginFrame()
    graph.removeSubtree(rootedAt: deadHost)
    graph.withCapturedResolveLifetimeScope(hostedBy: deadHost) {
      graph.reportResolvedLifetimeNode(detachedAfterDeath)
    }
    #expect(
      !graph.lifetimeAnchors.anchors(for: detachedAfterDeath.viewNodeID)
        .contains(.hostedDetached(deadHost.viewNodeID))
    )
  }

  @Test("a candidate removed before scope close needs no lifetime classification")
  func sameFrameRemovedCandidateIsIgnored() throws {
    let graph = ViewGraph()
    let host = evaluateStoredNode(graph, named: "Host")
    let removed = evaluateStoredNode(graph, named: "Removed")
    let unclassifiedBefore = SoundnessProbeConfiguration.unclassifiedResolvedNodeCount

    graph.beginFrame()
    graph.withResolveLifetimeScope(hostedBy: host) {
      graph.reportResolvedLifetimeNode(removed)
      graph.removeSubtree(
        rootedAt: removed,
        policy: .ordinary.ignoringLifetimeAnchors(true)
      )
    }

    #expect(graph.nodeForViewNodeID(removed.viewNodeID) == nil)
    #expect(SoundnessProbeConfiguration.unclassifiedResolvedNodeCount == unclassifiedBefore)
  }

  private func evaluateStoredNode(
    _ graph: ViewGraph,
    named name: String
  ) -> ViewNode {
    let identity = testIdentity("ResolveLifetimeScope", name)
    let node = graph.beginEvaluation(identity: identity, invalidator: nil)
    _ = graph.finishEvaluation(
      node,
      resolved: ResolvedNode(identity: identity, kind: .view(name)),
      accessedStateSlots: 0
    )
    return node
  }
}
