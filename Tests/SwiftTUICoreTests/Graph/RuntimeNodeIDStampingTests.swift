import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@MainActor
@Suite("Runtime node ID stamping")
struct RuntimeNodeIDStampingTests {
  @Test("freshly constructed nodes are unstamped")
  func freshConstructionIsUnstamped() {
    let node = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root
    )

    #expect(node.viewNodeID == nil)
    #expect(node.subtreeRuntimeNodeIDsStamped == false)
  }

  @Test("construction with a runtime node ID and no children is fully stamped")
  func stampedLeafConstructionIsFullyStamped() {
    let node = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 7),
      identity: testIdentity("Root"),
      kind: .root
    )

    #expect(node.subtreeRuntimeNodeIDsStamped)
  }

  @Test("construction with one unstamped child is not fully stamped")
  func unstampedChildBlocksFullStamp() {
    let node = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 7),
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Leaf"),
          kind: .view("Leaf")
        )
      ]
    )

    #expect(node.subtreeRuntimeNodeIDsStamped == false)
  }

  @Test("construction with stamped children is fully stamped")
  func stampedChildrenPropagateFullStamp() {
    let node = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 7),
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 8),
          identity: testIdentity("Root", "Leaf"),
          kind: .view("Leaf")
        )
      ]
    )

    #expect(node.subtreeRuntimeNodeIDsStamped)
  }

  @Test("the public children setter recomputes the stamped flag")
  func childrenSetterRecomputesStampedFlag() {
    var node = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 7),
      identity: testIdentity("Root"),
      kind: .root
    )
    #expect(node.subtreeRuntimeNodeIDsStamped)

    node.children = [
      ResolvedNode(
        identity: testIdentity("Root", "Leaf"),
        kind: .view("Leaf")
      )
    ]
    #expect(node.subtreeRuntimeNodeIDsStamped == false)

    node.children = [
      ResolvedNode(
        viewNodeID: ViewNodeID(rawValue: 8),
        identity: testIdentity("Root", "Leaf"),
        kind: .view("Leaf")
      )
    ]
    #expect(node.subtreeRuntimeNodeIDsStamped)
  }

  @Test("setChildrenPreservingDerivedState preserves the stamped flag by design")
  func preservingSetterKeepsStampedFlag() {
    // Animation tick frames replace children with same-shape interpolated
    // copies that carry the same runtime node IDs, so the preserving setter
    // deliberately skips the recompute. Overlay-injected trees that violate
    // the shape contract never re-enter graph applies.
    var node = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 7),
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          viewNodeID: ViewNodeID(rawValue: 8),
          identity: testIdentity("Root", "Leaf"),
          kind: .view("Leaf")
        )
      ]
    )
    #expect(node.subtreeRuntimeNodeIDsStamped)

    node.setChildrenPreservingDerivedState([
      ResolvedNode(
        identity: testIdentity("Root", "Leaf"),
        kind: .view("Leaf")
      )
    ])
    #expect(node.subtreeRuntimeNodeIDsStamped)
  }

  @Test("applying a fresh snapshot stamps every committed node")
  func applyStampsEveryCommittedNode() {
    let graph = ViewGraph()
    _ = graph.applySnapshot(threeLevelSnapshot())

    let committed = graph.snapshot()

    expectFullyStamped(committed)
  }

  @Test("re-applying an already-stamped snapshot keeps stamps identical")
  func reapplyKeepsStampsIdentical() {
    let graph = ViewGraph()
    _ = graph.applySnapshot(threeLevelSnapshot())
    let first = graph.snapshot()
    expectFullyStamped(first)

    _ = graph.applySnapshot(first)
    let second = graph.snapshot()

    expectStampsEqual(first, second)
  }

  @Test("count-mismatched apply does not claim the stamped flag")
  func countMismatchedApplyRefusesStampedFlag() throws {
    // Group splices and passthrough bodies legitimately hand a parent a
    // resolved child whose own children do not align 1:1 with the child
    // node's live children. The stamping walk cannot descend there, so it
    // cannot verify that the spliced stamps were written against this live
    // subtree — capture-host splices (the toolbar reconcile) inject children
    // stamped by *other* live nodes. Claiming subtree completeness here let
    // later applies fast-path over those foreign stamps (the gallery
    // tab-switch stamp-coherence crash), so the walk must refuse the flag
    // and leave the subtree to the slow restamping path.
    let graph = ViewGraph()
    _ = graph.applySnapshot(
      ResolvedNode(
        identity: testIdentity("Root"),
        kind: .root,
        children: [
          ResolvedNode(
            identity: testIdentity("Root", "Branch"),
            kind: .view("Branch")
          )
        ]
      )
    )
    let committed = graph.snapshot()
    let rootStamp = try #require(committed.viewNodeID)
    let branchStamp = try #require(committed.children[0].viewNodeID)
    let rootNodeUnwrapped = try #require(graph.nodeForViewNodeID(rootStamp))
    let branchNodeUnwrapped = try #require(graph.nodeForViewNodeID(branchStamp))
    let stampedGrandchild = ResolvedNode(
      viewNodeID: ViewNodeID(rawValue: 99),
      identity: testIdentity("Root", "Branch", "Spliced"),
      kind: .view("Spliced")
    )
    var branchPayload = committed.children[0]
    branchPayload.viewNodeID = nil
    branchPayload.children = [stampedGrandchild]
    var rootPayload = committed
    rootPayload.viewNodeID = nil
    rootPayload.children = [branchPayload]

    rootNodeUnwrapped.apply(
      resolved: rootPayload,
      children: [branchNodeUnwrapped]
    )

    let reapplied = rootNodeUnwrapped.snapshot()
    #expect(reapplied.subtreeRuntimeNodeIDsStamped == false)
    #expect(reapplied.viewNodeID == rootNodeUnwrapped.viewNodeID)
    #expect(reapplied.children[0].viewNodeID == branchNodeUnwrapped.viewNodeID)
    #expect(reapplied.children[0].children[0].viewNodeID == ViewNodeID(rawValue: 99))
  }

  private func threeLevelSnapshot() -> ResolvedNode {
    ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "Branch"),
          kind: .view("Branch"),
          children: [
            ResolvedNode(
              identity: testIdentity("Root", "Branch", "LeafA"),
              kind: .view("LeafA")
            ),
            ResolvedNode(
              identity: testIdentity("Root", "Branch", "LeafB"),
              kind: .view("LeafB")
            ),
          ]
        )
      ]
    )
  }

  private func expectFullyStamped(
    _ node: ResolvedNode,
    path: String = "root"
  ) {
    #expect(node.viewNodeID != nil, "missing stamp at \(path)")
    #expect(node.subtreeRuntimeNodeIDsStamped, "flag false at \(path)")
    for (index, child) in node.children.enumerated() {
      expectFullyStamped(child, path: "\(path).\(index)")
    }
  }

  private func expectStampsEqual(
    _ lhs: ResolvedNode,
    _ rhs: ResolvedNode,
    path: String = "root"
  ) {
    #expect(lhs.viewNodeID == rhs.viewNodeID, "stamp diverged at \(path)")
    #expect(lhs.children.count == rhs.children.count, "shape diverged at \(path)")
    for (index, pair) in zip(lhs.children, rhs.children).enumerated() {
      expectStampsEqual(pair.0, pair.1, path: "\(path).\(index)")
    }
  }
}
