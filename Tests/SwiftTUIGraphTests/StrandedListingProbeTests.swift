import Testing

@testable import SwiftTUIGraph

// Teeth for the stranded-listing oracle (residual 2 of the reuse/freshness
// quirk register). The invariant it enforces — a node that still CLAIMS
// ownership of a child seated under a different live parent — is the state the
// gallery Tab-wrap stamp-coherence crash resolved from, and it is now swept
// graph-wide at the finalize barrier on every probe-sampled frame.
//
// A clean sweep is worthless without a demonstration that the sweep can be
// dirty, so these build the defect shape directly: re-seat a child WITHOUT the
// notification `reclaimForeignParentedChildren` sends, which is exactly what
// the fix installs.
@MainActor
@Suite("Stranded-listing probe")
struct StrandedListingProbeTests {
  /// Builds `root -> (claimant -> child, thief)` through one committed frame
  /// and returns the graph plus the three nodes.
  private func makeGraph() throws -> (
    graph: ViewGraph, claimant: ViewNode, child: ViewNode, thief: ViewNode
  ) {
    let graph = ViewGraph()
    let rootIdentity = testIdentity("Root")
    let claimantIdentity = testIdentity("Root", "Claimant")
    let childIdentity = testIdentity("Root", "Claimant", "Child")
    let thiefIdentity = testIdentity("Root", "Thief")

    graph.beginFrame()
    let root = graph.beginEvaluation(identity: rootIdentity, invalidator: nil)
    let claimant = graph.beginEvaluation(identity: claimantIdentity, invalidator: nil)
    let child = graph.beginEvaluation(identity: childIdentity, invalidator: nil)
    let childResolved = try #require(
      graph.finishEvaluation(
        child,
        resolved: ResolvedNode(identity: childIdentity, kind: .view("Child")),
        accessedStateSlots: 0
      )
    )
    let claimantResolved = try #require(
      graph.finishEvaluation(
        claimant,
        resolved: ResolvedNode(
          identity: claimantIdentity,
          kind: .view("Claimant"),
          children: [childResolved]
        ),
        accessedStateSlots: 0
      )
    )
    let thief = graph.beginEvaluation(identity: thiefIdentity, invalidator: nil)
    let thiefResolved = try #require(
      graph.finishEvaluation(
        thief,
        resolved: ResolvedNode(identity: thiefIdentity, kind: .view("Thief")),
        accessedStateSlots: 0
      )
    )
    _ = graph.finishEvaluation(
      root,
      resolved: ResolvedNode(
        identity: rootIdentity,
        kind: .root,
        children: [claimantResolved, thiefResolved]
      ),
      accessedStateSlots: 0
    )
    _ = graph.finalizeFrame(rootIdentity: rootIdentity)

    return (graph, claimant, child, thief)
  }

  @Test("a settled graph reports no stranded listings")
  func settledGraphIsClean() throws {
    let (graph, claimant, child, _) = try makeGraph()
    #expect(claimant.claimsOwnershipOfListedChildren)
    #expect(child.parent === claimant)
    #expect(graph.strandedFreshServableViolations() == [])
  }

  @Test("an unnotified re-seat is reported")
  func unnotifiedReseatIsReported() throws {
    let (graph, _, child, thief) = try makeGraph()

    // The defect: a competing apply takes the child's `parent` slot without
    // telling the previous parent. `reclaimForeignParentedChildren` sends that
    // notification in production; skipping it is precisely the pre-fix
    // behavior behind the Tab-wrap stamp-coherence crash.
    child.parent = thief

    let violations = graph.strandedFreshServableViolations()
    #expect(violations.count == 1)
    #expect(violations.first?.contains("Root/Claimant") == true)
    #expect(violations.first?.contains("Root/Claimant/Child") == true)
    #expect(violations.first?.contains("Root/Thief") == true)
  }

  @Test("the notification withdraws the claim and quiets the sweep")
  func notificationWithdrawsTheClaim() throws {
    let (graph, claimant, child, thief) = try makeGraph()
    child.parent = thief
    #expect(graph.strandedFreshServableViolations().count == 1)

    // What the fix actually does. The listing survives — it is the claim that
    // is withdrawn, and withdrawing it is what denies value-blind service.
    claimant.noteChildReseatedAway()

    #expect(claimant.children.contains { $0 === child })
    #expect(!claimant.claimsOwnershipOfListedChildren)
    #expect(graph.strandedFreshServableViolations() == [])
  }
}
