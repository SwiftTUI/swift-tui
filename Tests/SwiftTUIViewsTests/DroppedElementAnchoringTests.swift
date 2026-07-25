import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph
@testable import SwiftTUIViews

/// Lifetime anchoring for elements that resolve to nothing and are dropped.
///
/// `DeclaredChildConsumptionPolicy.forEachIteration` does not eagerly anchor a
/// dropped empty element while `.declaredBuilder` does, and nothing recorded
/// why. These tests settle it: the anchor does not depend on that call at all.
/// `resolveView` reports every result to the enclosing lifetime scope, and
/// `closeResolveLifetimeScope` anchors any observed node that reached close
/// without a durable owner. Both paths therefore converge on the same
/// `.hostedDetached` anchor to the same host; the eager call only moves it
/// earlier.
///
/// Verified by A/B: with `.declaredBuilder.reportsDroppedEmpty` flipped off,
/// the declared-builder drop below stays anchored and unclassified stays flat.
/// These cases are kept as the regression pin for both paths — the guarantee
/// lives in the scope-close catch-all, so a change there would silently strand
/// dropped elements everywhere at once.
@MainActor
struct DroppedElementAnchoringTests {
  private struct DroppedRows: View {
    let rows: [Int]

    var body: some View {
      ForEach(rows, id: \.self) { row in
        // Odd rows resolve to EmptyView. `_ = row` keeps the branch from being
        // folded away, mirroring the `_ = state` Void-expression shape the
        // declared-builder path documents.
        if row.isMultiple(of: 2) {
          Text("row-\(row)")
        }
      }
    }
  }

  private func resolveDroppedRows() -> (graph: ViewGraph, resolved: ResolvedNode) {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("ForEachDroppedRow"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    let resolved = resolveView(DroppedRows(rows: [0, 1, 2, 3]), in: context)
    return (graph, resolved)
  }

  /// The declared-builder drop shape: an explicit `EmptyView` element between
  /// siblings, resolved at its own identity and then dropped by the child walk.
  private struct DroppedInlineElement: View {
    var body: some View {
      Text("leading")
      EmptyView()
      Text("trailing")
    }
  }

  private func resolveDroppedInline() -> (graph: ViewGraph, resolved: ResolvedNode) {
    let graph = ViewGraph()
    graph.beginFrame()
    var context = ResolveContext(
      identity: testIdentity("DroppedInline"),
      environmentValues: .init(),
      applyEnvironmentValues: true
    )
    context.viewGraph = graph
    return (graph, resolveView(DroppedInlineElement(), in: context))
  }

  @Test("a dropped inline element is anchored on the declared-builder path too")
  func droppedInlineElementIsAnchored() {
    let before = SoundnessProbeConfiguration.unclassifiedResolvedNodeCount
    let (graph, resolved) = resolveDroppedInline()

    #expect(SoundnessProbeConfiguration.unclassifiedResolvedNodeCount == before)

    var unanchored: [String] = []
    for (nodeID, node) in graph.nodesByNodeID where node.parent == nil {
      guard nodeID != graph.root?.viewNodeID, nodeID != resolved.viewNodeID else {
        continue
      }
      if graph.lifetimeAnchors.anchors(for: nodeID).isEmpty {
        unanchored.append("\(nodeID) kind=\(node.kind) identity=\(node.identity.path)")
      }
    }
    #expect(unanchored.isEmpty, "parent-less nodes with no lifetime anchor: \(unanchored)")
  }

  @Test("dropped rows leave no unclassified lifetime behind")
  func droppedRowsAreClassified() {
    // The direct strand oracle. `closeResolveLifetimeScope` records an
    // unclassified node for any observed node it cannot attribute to a durable
    // owner — and asserts the set is empty, so a strand here would trap in a
    // debug test build rather than merely count.
    let before = SoundnessProbeConfiguration.unclassifiedResolvedNodeCount
    let (graph, resolved) = resolveDroppedRows()
    _ = graph
    _ = resolved
    #expect(SoundnessProbeConfiguration.unclassifiedResolvedNodeCount == before)
  }

  @Test("only the even rows survive into the resolved children")
  func onlyKeptRowsRemain() {
    // Establishes that rows really are being dropped — otherwise the anchoring
    // question would be vacuous because nothing was consumed.
    let (_, resolved) = resolveDroppedRows()
    let texts = collectKinds(of: resolved).filter { $0 == .view("Text") }
    #expect(texts.count == 2)
  }

  @Test("every live node the resolve minted carries a durable anchor")
  func mintedNodesAreAnchored() {
    // The substantive claim: whatever the dropped rows minted is owned by
    // something. An unanchored, unparented node is the strand class — reachable
    // by no teardown path and reclaimed by none either.
    let (graph, resolved) = resolveDroppedRows()

    // The top-level result is unparented by construction here: this harness
    // resolves in isolation, so nothing commits it into a tree. Every node
    // BELOW it is the population under test.
    var unanchored: [String] = []
    for (nodeID, node) in graph.nodesByNodeID where node.parent == nil {
      guard nodeID != graph.root?.viewNodeID, nodeID != resolved.viewNodeID else {
        continue
      }
      if graph.lifetimeAnchors.anchors(for: nodeID).isEmpty {
        unanchored.append("\(nodeID) kind=\(node.kind) identity=\(node.identity.path)")
      }
    }

    #expect(
      unanchored.isEmpty,
      "parent-less nodes with no lifetime anchor: \(unanchored)"
    )
  }
}

private func collectKinds(of node: ResolvedNode) -> [NodeKind] {
  var kinds: [NodeKind] = [node.kind]
  for child in node.children {
    kinds.append(contentsOf: collectKinds(of: child))
  }
  return kinds
}
