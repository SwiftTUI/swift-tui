import Testing

@testable import SwiftTUIGraph

@Suite("LifetimeAnchorIndex")
struct LifetimeAnchorIndexTests {
  @Test("multiple anchor kinds coexist and kind replacement is exact")
  func multipleKindsAndExactReplacement() {
    let target = nodeID(7)
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .parent(nodeID(1)), for: target)
    index.insert(anchor: .committedValue(nodeID(2)), for: target)
    index.insert(anchor: .entityHome(EntityIdentity("seven")), for: target)

    index.replaceAnchors(
      ofKind: .parent,
      for: target,
      with: [.parent(nodeID(3))]
    )

    #expect(
      index.anchors(for: target)
        == [
          .parent(nodeID(3)),
          .committedValue(nodeID(2)),
          .entityHome(EntityIdentity("seven")),
        ]
    )
    #expect(index.targets(of: .parent(nodeID(1))).isEmpty)
    #expect(index.targets(of: .parent(nodeID(3))) == [target])
    #expect(index.isInverseConsistent)
  }

  @Test("detached roots re-home exclusively")
  func detachedRehomeIsExclusive() {
    let root = nodeID(9)
    var index = LifetimeAnchorIndex()
    index.rehomeDetachedRoot(root, to: nodeID(1))
    index.rehomeDetachedRoot(root, to: nodeID(2))

    #expect(index.anchors(for: root) == [.hostedDetached(nodeID(2))])
    #expect(index.targets(of: .hostedDetached(nodeID(1))).isEmpty)
    #expect(index.targets(of: .hostedDetached(nodeID(2))) == [root])
    #expect(index.isInverseConsistent)
  }

  @Test("navigation replacement returns exactly departed targets")
  func navigationReplacementReturnsDepartures() {
    var index = LifetimeAnchorIndex()
    let host = nodeID(1)
    #expect(
      index.replaceNavigationSurfaces(
        hostedBy: host,
        with: [nodeID(2), nodeID(3)]
      ).isEmpty
    )

    let departed = index.replaceNavigationSurfaces(
      hostedBy: host,
      with: [nodeID(3), nodeID(4)]
    )

    #expect(departed == [nodeID(2)])
    #expect(index.targets(of: .navigationSurface(host)) == [nodeID(3), nodeID(4)])
    #expect(index.isInverseConsistent)
  }

  @Test("node removal cleans incoming and outgoing edges without touching peers")
  func nodeRemovalCleansBothDirections() {
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .parent(nodeID(1)), for: nodeID(2))
    index.insert(anchor: .hostedDetached(nodeID(2)), for: nodeID(3))
    index.insert(anchor: .committedValue(nodeID(4)), for: nodeID(3))
    index.insert(anchor: .navigationSurface(nodeID(2)), for: nodeID(5))

    #expect(index.removalTargets(of: nodeID(2)) == [nodeID(3), nodeID(5)])
    index.removeNode(nodeID(2))

    #expect(index.anchors(for: nodeID(2)).isEmpty)
    #expect(index.targets(of: nodeID(2)).isEmpty)
    #expect(index.anchors(for: nodeID(3)) == [.committedValue(nodeID(4))])
    #expect(index.anchors(for: nodeID(5)).isEmpty)
    #expect(index.isInverseConsistent)
  }

  @Test("cycles terminate and shortest anchor chains are deterministic")
  func cycleClosureIsDeterministic() {
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .hostedDetached(nodeID(3)), for: nodeID(1))
    index.insert(anchor: .parent(nodeID(2)), for: nodeID(3))
    index.insert(anchor: .parent(nodeID(1)), for: nodeID(2))
    index.insert(anchor: .committedValue(nodeID(1)), for: nodeID(4))
    let context = LifetimeReachabilityContext(candidateRootID: nodeID(1))

    let first = index.reachableNodeIDs(context: context)
    let second = index.reachableNodeIDs(context: context)

    #expect(first == second)
    #expect(first.nodeIDs == [nodeID(1), nodeID(2), nodeID(3), nodeID(4)])
    #expect(
      first.anchorChain(to: nodeID(3))
        == [
          .root(nodeID(1)),
          .anchor(.parent(nodeID(1)), target: nodeID(2)),
          .anchor(.parent(nodeID(2)), target: nodeID(3)),
        ]
    )
  }

  @Test("entity homes seed reachability only when active and exactly qualified")
  func entityHomeQualificationIsExact() {
    let entity = EntityIdentity("row")
    let target = nodeID(8)
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .entityHome(entity), for: target)

    let inactive = LifetimeReachabilityContext(
      candidateRootID: nodeID(1),
      liveEntityHomeByIdentity: [entity: target]
    )
    #expect(!index.reachableNodeIDs(context: inactive).nodeIDs.contains(target))

    let rehomed = LifetimeReachabilityContext(
      candidateRootID: nodeID(1),
      activeEntityIdentities: [entity],
      liveEntityHomeByIdentity: [entity: nodeID(9)]
    )
    #expect(!index.reachableNodeIDs(context: rehomed).nodeIDs.contains(target))

    let exact = LifetimeReachabilityContext(
      candidateRootID: nodeID(1),
      activeEntityIdentities: [entity],
      liveEntityHomeByIdentity: [entity: target]
    )
    #expect(index.reachableNodeIDs(context: exact).nodeIDs.contains(target))
    #expect(
      index.anchorChain(to: target, context: exact)
        == [.entityHome(entity, target)]
    )
  }

  @Test("removal cascades exclude internal anchors and parent suppresses evaluation host")
  func removalCascadeAndEvaluationHostPrecedence() {
    let target = nodeID(3)
    let parent = nodeID(2)
    let evaluationHost = nodeID(4)
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .parent(parent), for: target)
    index.insert(anchor: .evaluationHost(evaluationHost), for: target)
    let context = LifetimeReachabilityContext(candidateRootID: nodeID(1))

    let suppressed = index.keepDecision(
      for: target,
      removalCascade: [parent, target],
      context: context
    )
    #expect(!suppressed.shouldKeep)
    #expect(suppressed.reason == .noAnchorOutsideRemovalCascade)

    index.remove(anchor: .parent(parent), for: target)
    let unsuppressed = index.keepDecision(
      for: target,
      removalCascade: [parent, target],
      context: context
    )
    #expect(unsuppressed.shouldKeep)
    #expect(unsuppressed.reason == .anchor(.evaluationHost(evaluationHost)))

    let objectParentSuppressed = index.keepDecision(
      for: target,
      removalCascade: [parent, target],
      context: LifetimeReachabilityContext(
        candidateRootID: nodeID(1),
        parentedNodeIDs: [target]
      )
    )
    #expect(!objectParentSuppressed.shouldKeep)
  }

  @Test("unreachable forensics is bounded and node-ID ordered")
  func unreachableForensicsIsDeterministic() {
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .parent(nodeID(1)), for: nodeID(4))
    index.insert(anchor: .hostedDetached(nodeID(7)), for: nodeID(3))
    let context = LifetimeReachabilityContext(candidateRootID: nodeID(1))

    let first = index.unreachableNodeForensics(
      storedNodeIDs: [nodeID(1), nodeID(2), nodeID(3), nodeID(4), nodeID(5)],
      context: context,
      limit: 2
    )
    let second = index.unreachableNodeForensics(
      storedNodeIDs: [nodeID(5), nodeID(4), nodeID(3), nodeID(2), nodeID(1)],
      context: context,
      limit: 2
    )

    #expect(first == second)
    #expect(first.map(\.nodeID) == [nodeID(2), nodeID(3)])
    #expect(first[1].incomingAnchors == [.hostedDetached(nodeID(7))])
  }

  @Test("inverse validation reports either one-sided corruption")
  func inverseValidationFindsCorruption() {
    let target = nodeID(2)
    let anchor = LifetimeAnchor.parent(nodeID(1))
    var forwardOnly = LifetimeAnchorIndex(
      anchorsByNodeID: [target: [anchor]]
    )
    #expect(
      forwardOnly.inverseConsistencyViolations()
        == [
          LifetimeAnchorInverseViolation(
            direction: .forwardMissingFromInverse,
            nodeID: target,
            anchor: anchor
          )
        ]
    )

    forwardOnly = LifetimeAnchorIndex(
      nodeIDsByAnchor: [anchor: [target]]
    )
    #expect(
      forwardOnly.inverseConsistencyViolations()
        == [
          LifetimeAnchorInverseViolation(
            direction: .inverseMissingFromForward,
            nodeID: target,
            anchor: anchor
          )
        ]
    )
  }

  @Test("bounded randomized mutations never split the inverse")
  func randomizedMutationsPreserveInverse() {
    var random = DeterministicLifetimeRandom(seed: 0xC0FFEE)
    var index = LifetimeAnchorIndex()
    let entities = (0..<4).map { EntityIdentity("entity-\($0)") }

    for _ in 0..<2_000 {
      let target = nodeID(random.next(upperBound: 16) + 1)
      let source = nodeID(random.next(upperBound: 16) + 1)
      let anchor: LifetimeAnchor =
        switch random.next(upperBound: 6) {
        case 0: .parent(source)
        case 1: .committedValue(source)
        case 2: .hostedDetached(source)
        case 3: .entityHome(entities[random.next(upperBound: entities.count)])
        case 4: .navigationSurface(source)
        default: .evaluationHost(source)
        }

      switch random.next(upperBound: 5) {
      case 0:
        index.insert(anchor: anchor, for: target)
      case 1:
        index.remove(anchor: anchor, for: target)
      case 2:
        index.rehomeDetachedRoot(target, to: source)
      case 3:
        index.removeNode(target)
      default:
        _ = index.replaceNavigationSurfaces(
          hostedBy: source,
          with: [target]
        )
      }
      #expect(index.isInverseConsistent)
    }
  }

  @Test("reasoned teardown work deduplicates and consumes by node")
  func teardownWorkOperationsAreExact() {
    var work = TeardownBarrierWork()
    work.enqueue(.entityRoutedRemoval, for: nodeID(1))
    work.enqueue(.entityRoutedRemoval, for: nodeID(1))
    work.enqueue(.absorbedShadow, for: nodeID(1))
    work.enqueue(.departedNavigationSurface, for: nodeID(2))

    #expect(work.nodeIDs == [nodeID(1), nodeID(2)])
    #expect(work.reasonCount == 3)
    #expect(
      work.consumeReasons(for: nodeID(1))
        == [.entityRoutedRemoval, .absorbedShadow]
    )
    #expect(work.reasons(for: nodeID(1)).isEmpty)
    work.removeNode(nodeID(2))
    #expect(work.isEmpty)
  }

  @Test("parent edge neuter breaks its directed reachability fixture")
  func parentEdgeNeuterBites() {
    expectEdgeNeuterBites(.parent(nodeID(1)))
  }

  @Test("committed-value edge neuter breaks its directed reachability fixture")
  func committedValueEdgeNeuterBites() {
    expectEdgeNeuterBites(.committedValue(nodeID(1)))
  }

  @Test("hosted-detached edge neuter breaks its directed reachability fixture")
  func hostedDetachedEdgeNeuterBites() {
    expectEdgeNeuterBites(.hostedDetached(nodeID(1)))
  }

  @Test("navigation-surface edge neuter breaks its directed reachability fixture")
  func navigationSurfaceEdgeNeuterBites() {
    expectEdgeNeuterBites(.navigationSurface(nodeID(1)))
  }

  @Test("evaluation-host edge neuter breaks its directed reachability fixture")
  func evaluationHostEdgeNeuterBites() {
    expectEdgeNeuterBites(.evaluationHost(nodeID(1)))
  }

  @Test("entity-home edge neuter breaks its directed reachability fixture")
  func entityHomeEdgeNeuterBites() {
    let entity = EntityIdentity("neuter")
    let target = nodeID(2)
    var index = LifetimeAnchorIndex()
    index.insert(anchor: .entityHome(entity), for: target)
    let context = LifetimeReachabilityContext(
      candidateRootID: nodeID(1),
      activeEntityIdentities: [entity],
      liveEntityHomeByIdentity: [entity: target]
    )
    #expect(index.reachableNodeIDs(context: context).nodeIDs.contains(target))
    index.remove(anchor: .entityHome(entity), for: target)
    #expect(!index.reachableNodeIDs(context: context).nodeIDs.contains(target))
  }
}

@MainActor
@Suite("Lifetime relation checkpoint integration")
struct LifetimeRelationCheckpointTests {
  @Test("checkpoint restore reproduces lifetime relation and teardown work exactly")
  func checkpointRoundTrip() {
    let graph = ViewGraph()
    graph.lifetimeAnchors.insert(
      anchor: .hostedDetached(nodeID(1)),
      for: nodeID(2)
    )
    graph.teardownBarrierWork.enqueue(
      .resolveScopeScratch,
      for: nodeID(2)
    )
    let before = graph.debugTotalStateSnapshot()
    let checkpoint = graph.makeCheckpoint()

    graph.lifetimeAnchors.rehomeDetachedRoot(nodeID(2), to: nodeID(3))
    graph.teardownBarrierWork.enqueue(.absorbedShadow, for: nodeID(4))
    #expect(graph.debugTotalStateSnapshot() != before)

    graph.restoreCheckpoint(checkpoint)
    #expect(graph.debugTotalStateSnapshot() == before)
    #expect(graph.lifetimeAnchors.isInverseConsistent)
  }
}

private struct DeterministicLifetimeRandom {
  private var state: UInt64

  init(seed: UInt64) {
    state = seed
  }

  mutating func next(upperBound: Int) -> Int {
    state = state &* 6_364_136_223_846_793_005 &+ 1_442_695_040_888_963_407
    return Int(state % UInt64(upperBound))
  }
}

private func nodeID(_ rawValue: Int) -> ViewNodeID {
  ViewNodeID(rawValue: UInt64(rawValue))
}

private func expectEdgeNeuterBites(_ anchor: LifetimeAnchor) {
  let target = nodeID(2)
  var index = LifetimeAnchorIndex()
  index.insert(anchor: anchor, for: target)
  let context = LifetimeReachabilityContext(candidateRootID: nodeID(1))
  #expect(index.reachableNodeIDs(context: context).nodeIDs.contains(target))
  index.remove(anchor: anchor, for: target)
  #expect(!index.reachableNodeIDs(context: context).nodeIDs.contains(target))
}
