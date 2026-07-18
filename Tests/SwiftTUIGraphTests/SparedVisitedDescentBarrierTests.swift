import Testing

@testable import SwiftTUIGraph

/// The teardown-coherence strand under the toolbar capture-host seam
/// (gallery fuzzer case-139): a departing-subtree descent spares any node
/// visited this frame (the re-adoption keep-guard), but "visited" also holds
/// for a node a SUPERSEDED same-frame pass resolved and the committed pass
/// dropped. The departing wrapper's teardown then clears every edge naming
/// the spared node, no later teardown path can reach it, and the F91 census
/// flags it stored-but-unreachable — one stranded ButtonBody island per
/// dropped toolbar item. The `.sparedVisitedDescent` barrier verdict pins
/// both directions: an anchor-less spare is reclaimed at the frame barrier,
/// and a genuinely re-adopted spare (durably anchored by its adopting
/// parent's apply) survives it.
@MainActor
@Suite("Spared visited descent barrier verdict")
struct SparedVisitedDescentBarrierTests {
  private let rootIdentity = testIdentity("Root")
  private let wrapperIdentity = testIdentity("Root", "Wrapper")
  private let islandIdentity = testIdentity("Root", "Wrapper", "Island")

  private func buildCommittedWrapperIsland(
    in graph: ViewGraph
  ) {
    graph.beginFrame()
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let wrapperNode = graph.beginEvaluation(identity: wrapperIdentity, invalidator: nil)
    let islandNode = graph.beginEvaluation(identity: islandIdentity, invalidator: nil)
    let resolvedIsland =
      graph.finishEvaluation(
        islandNode,
        resolved: ResolvedNode(identity: islandIdentity, kind: .view("Island")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: islandIdentity, kind: .view("Island"))
    let resolvedWrapper =
      graph.finishEvaluation(
        wrapperNode,
        resolved: ResolvedNode(
          identity: wrapperIdentity,
          kind: .view("Wrapper"),
          children: [resolvedIsland]
        ),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: wrapperIdentity, kind: .view("Wrapper"))
    graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: [resolvedWrapper]),
      accessedStateSlots: 0
    )
    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)
  }

  @Test("an anchor-less visited spare is reclaimed at the barrier")
  func anchorlessVisitedSpareIsReclaimedAtTheBarrier() {
    let graph = ViewGraph()
    buildCommittedWrapperIsland(in: graph)

    // Next frame: a superseded pass re-visits the island …
    graph.beginFrame()
    let islandNode = graph.beginEvaluation(identity: islandIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      islandNode,
      resolved: ResolvedNode(identity: islandIdentity, kind: .view("Island")),
      accessedStateSlots: 0
    )
    // … and the committed pass drops the wrapper. The structural child diff
    // tears the wrapper down; the descent reaches the visited island and
    // spares it — the provisional keep this suite pins.
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: []),
      accessedStateSlots: 0
    )
    #expect(
      graph.nodeIfExists(for: wrapperIdentity) == nil,
      "the dropped wrapper must be torn down by the structural child diff"
    )
    #expect(
      graph.nodeIfExists(for: islandIdentity) === islandNode,
      "the visited island must be spared by the descent (the shape under test)"
    )
    #expect(
      graph.teardownBarrierWork.reasons(for: islandNode.viewNodeID)
        .contains(.sparedVisitedDescent),
      "the visited-spare must enqueue the node for the barrier verdict"
    )

    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    #expect(
      graph.nodeIfExists(for: islandIdentity) == nil,
      "an anchor-less visited spare must be reclaimed at the frame barrier"
    )
    let violation = graph.debugTeardownCoherenceViolation()
    #expect(
      violation == nil,
      "the spared island stranded stored node(s): \(violation?.detail ?? "")"
    )
  }

  @Test("a re-adopted visited spare survives the barrier")
  func readoptedVisitedSpareSurvivesTheBarrier() {
    let graph = ViewGraph()
    buildCommittedWrapperIsland(in: graph)

    // Next frame: the arriving generation re-adopts the island under a new
    // parent while the old wrapper departs.
    graph.beginFrame()
    let islandNode = graph.beginEvaluation(identity: islandIdentity, invalidator: nil)
    let resolvedIsland =
      graph.finishEvaluation(
        islandNode,
        resolved: ResolvedNode(identity: islandIdentity, kind: .view("Island")),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: islandIdentity, kind: .view("Island"))
    let adopterIdentity = testIdentity("Root", "Adopter")
    let adopterNode = graph.beginEvaluation(identity: adopterIdentity, invalidator: nil)
    let resolvedAdopter =
      graph.finishEvaluation(
        adopterNode,
        resolved: ResolvedNode(
          identity: adopterIdentity,
          kind: .view("Adopter"),
          children: [resolvedIsland]
        ),
        accessedStateSlots: 0
      ) ?? ResolvedNode(identity: adopterIdentity, kind: .view("Adopter"))
    let rootNode = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    _ = graph.finishEvaluation(
      rootNode,
      resolved: ResolvedNode(identity: rootIdentity, kind: .root, children: [resolvedAdopter]),
      accessedStateSlots: 0
    )

    let resolved = graph.snapshot(rootIdentity: rootIdentity)
    _ = graph.finalizeFrame(rootIdentity: rootIdentity, resolved: resolved, placed: nil)

    #expect(
      graph.nodeIfExists(for: islandIdentity) === islandNode,
      "a re-adopted visited spare must survive the barrier verdict"
    )
    let violation = graph.debugTeardownCoherenceViolation()
    #expect(
      violation == nil,
      "the re-adopted island left an incoherent store: \(violation?.detail ?? "")"
    )
  }
}
