import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Pins the resolve-time layout-offload disqualifier aggregate (F35): the
/// frame tail answers its offload-eligibility queries from
/// `customLayoutFallbackSummary` in O(1), so every mutation path that can
/// change a disqualifier must keep the summary current.
@MainActor
@Suite
struct ResolvedNodeOffloadSummaryTests {
  @Test("init aggregates layout-realized content boundaries bottom-up")
  func initAggregatesLayoutRealizedContent() {
    var leaf = makeNode("leaf")
    leaf.layoutRealizedContent = makeBoundary(for: leaf.identity)
    let root = makeNode("root", children: [makeNode("mid", children: [leaf])])

    #expect(root.customLayoutFallbackSummary.layoutRealizedContentCount == 1)
    #expect(root.customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceCount == 0)
    #expect(root.customLayoutFallbackSummary.count == 0)
  }

  @Test("layoutRealizedContent didSet keeps the summary current")
  func layoutRealizedContentDidSetRecomputes() {
    var target = makeNode("target")
    #expect(target.customLayoutFallbackSummary.layoutRealizedContentCount == 0)

    target.layoutRealizedContent = makeBoundary(for: target.identity)
    #expect(target.customLayoutFallbackSummary.layoutRealizedContentCount == 1)

    target.layoutRealizedContent = nil
    #expect(target.customLayoutFallbackSummary.layoutRealizedContentCount == 0)
  }

  @Test("indexedChildSource didSet records main-actor-only sources")
  func indexedChildSourceDidSetRecords() {
    var target = makeNode("target")
    // The bare protocol witness reports `canRunOnWorker == false`;
    // `IndexedChildSourceSnapshot` reports `true`.
    target.indexedChildSource = MainActorOnlyChildSource(
      identityRoot: target.identity
    )
    #expect(target.customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceCount == 1)

    target.indexedChildSource = IndexedChildSourceSnapshot(
      identityRoot: target.identity,
      measurementSignature: .init(elementPaths: ["sig"]),
      children: []
    )
    #expect(target.customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceCount == 0)
  }

  @Test("children setter re-aggregates disqualifiers from the new subtree")
  func childrenSetterReaggregates() {
    var child = makeNode("child")
    child.layoutRealizedContent = makeBoundary(for: child.identity)
    var root = makeNode("root")
    #expect(root.customLayoutFallbackSummary.layoutRealizedContentCount == 0)

    root.children = [child]
    #expect(root.customLayoutFallbackSummary.layoutRealizedContentCount == 1)

    root.children = []
    #expect(root.customLayoutFallbackSummary.layoutRealizedContentCount == 0)
  }

  @Test("worker-resolved children contribute their disqualifiers")
  func workerResolvedChildrenContribute() {
    var workerChild = makeNode("worker-child")
    workerChild.layoutRealizedContent = makeBoundary(for: workerChild.identity)
    var target = makeNode("target")
    target.indexedChildSource = IndexedChildSourceSnapshot(
      identityRoot: target.identity,
      measurementSignature: .init(elementPaths: ["sig"]),
      children: [workerChild]
    )

    #expect(target.customLayoutFallbackSummary.layoutRealizedContentCount == 1)
    #expect(target.customLayoutFallbackSummary.mainActorOnlyIndexedChildSourceCount == 0)
  }
}

private func makeNode(
  _ name: String,
  children: [ResolvedNode] = []
) -> ResolvedNode {
  ResolvedNode(
    identity: Identity(components: [name]),
    kind: .view(name),
    children: children
  )
}

@MainActor
private func makeBoundary(for identity: Identity) -> LayoutRealizedContentBoundary {
  LayoutRealizedContentBoundary(
    identity: identity,
    sizingPolicy: .fillsProposal(unspecifiedIdeal: .init(width: 1, height: 1)),
    safeAreaInsets: .init(),
    cellPixelMetrics: .estimated,
    pointerInputCapabilities: .cellOnly,
    debugName: "OffloadSummaryTestContent",
    handle: LayoutDependentContentHandle(OffloadSummaryTestRealizer())
  )
}

@MainActor
private final class OffloadSummaryTestRealizer: LayoutDependentContentRealizer {
  var debugName: String { "OffloadSummaryTestContent" }

  func realize(in _: LayoutRealizationContext) -> [ResolvedNode] {
    []
  }
}

private struct MainActorOnlyChildSource: IndexedChildSource {
  let identityRoot: Identity
  var count: Int { 0 }
  var measurementSignature: IndexedChildMeasurementSignature {
    .init(elementPaths: ["main-actor-only"])
  }

  func child(at index: Int) -> ResolvedNode {
    ResolvedNode(identity: identityRoot, kind: .view("main-actor-only-child"))
  }
}
