import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

// STUI-688, STUI-930, STUI-937 and the indexed-measurement worker-snapshot
// fix motivate comparing a reused engine with a cold engine after A/B/A changes.
@Suite("Adversarial set A: measurement reuse")
struct AdversarialSetAMeasurementTests {
  @Test func setA061NestedIntrinsicSizeChangesAndReturns() {
    var changed = tree()
    changed.children[0].children[0].intrinsicSize = .init(width: 17, height: 5)
    compare([tree(), changed, tree()])
  }

  @Test func setA062ReorderedUnequalChildrenKeepTheirMeasurements() {
    var changed = tree()
    changed.children.reverse()
    compare([tree(), changed, tree()])
  }

  @Test func setA063RemovedAndReinsertedChildDoesNotBorrowSiblingSize() {
    var removed = tree()
    removed.children.removeFirst()
    var inserted = removed
    inserted.children.insert(tree().children[0], at: 1)
    compare([tree(), removed, inserted, tree()])
  }

  @Test func setA064StackAxisRoundTripRetiresAllocation() {
    var changed = tree()
    changed.layoutBehavior = .stack(
      axis: .horizontal, spacing: 2,
      horizontalAlignment: .leading, verticalAlignment: .top)
    compare([tree(), changed, tree()])
  }

  @Test func setA065AsymmetricPaddingChangesAtStableIdentity() {
    var changed = tree()
    changed.children[0].layoutBehavior = .padding(.init(top: 2, leading: 5, bottom: 1, trailing: 0))
    compare([tree(), changed, tree()])
  }

  @Test func setA066FrameAlignmentChangeRefreshesPlacementOnCacheHit() {
    var original = tree()
    original.layoutBehavior = .frame(width: 8, height: 8, alignment: .topLeading)
    original.children = [original.children[0]]
    var changed = original
    changed.layoutBehavior = .frame(width: 8, height: 8, alignment: .bottomTrailing)
    compare([original, changed, original])
  }

  @Test func setA067OffsetChangeRefreshesPlacementWithoutChangingSize() {
    var original = tree()
    original.layoutBehavior = .offset(x: 1, y: 2)
    original.children = [original.children[0]]
    var changed = original
    changed.layoutBehavior = .offset(x: -7, y: 3)
    compare([original, changed, original])
  }

  @Test func setA068MinimumMetadataChangesAfterProbe() {
    var changed = tree()
    changed.children[0].children[0].layoutMetadata = .init(minimumWidth: 12, minimumHeight: 4)
    compare([tree(), changed, tree()])
  }

  @Test func setA069WildcardWitnessCannotHideLaterNestedTypeAndSizeChange() {
    var original = tree()
    original.children[0].children[0].typeDiscriminator = ObjectIdentifier(Int.self)
    var wildcard = original
    wildcard.children[0].children[0].typeDiscriminator = nil
    var changed = original
    changed.children[0].children[0].typeDiscriminator = ObjectIdentifier(String.self)
    changed.children[0].children[0].intrinsicSize = .init(width: 11, height: 3)
    compare([original, wildcard, changed, original])
  }

  @Test func setA070NestedEmptyBranchCanRepopulateAfterProposalChurn() {
    var empty = tree()
    empty.children[0].children = []
    var changed = tree()
    changed.children[0].children.append(leaf(9, width: 14, height: 3))
    compare([tree(), empty, changed, tree()])
  }

  private func tree() -> ResolvedNode {
    let wrapper = ResolvedNode(
      viewNodeID: .init(rawValue: 2), identity: testIdentity("SetA", "wrapper"),
      kind: .view("Padding"),
      children: [leaf(3, width: 3, height: 2)],
      layoutBehavior: .padding(.init(top: 1, leading: 1, bottom: 0, trailing: 2)))
    return ResolvedNode(
      viewNodeID: .init(rawValue: 1), identity: testIdentity("SetA"), kind: .view("Stack"),
      children: [wrapper, leaf(4, width: 5, height: 1)],
      layoutBehavior: .stack(
        axis: .vertical, spacing: 1,
        horizontalAlignment: .leading, verticalAlignment: .top))
  }

  private func leaf(_ id: UInt64, width: Int, height: Int) -> ResolvedNode {
    .init(
      viewNodeID: .init(rawValue: id), identity: testIdentity("SetA", "leaf-\(id)"),
      kind: .view("Leaf"), intrinsicSize: .init(width: width, height: height))
  }

  private func compare(_ versions: [ResolvedNode]) {
    let cache = MeasurementCache()
    let warm = LayoutEngine(cache: cache)
    let proposals: [ProposedSize] = [
      .unspecified, .init(width: 20, height: 12), .init(width: 7, height: 4),
      .init(width: 0, height: 0), .init(width: 30, height: 20), .unspecified,
    ]
    for (generation, node) in versions.enumerated() {
      for proposal in proposals {
        let cold = LayoutEngine()
        let expected = cold.measure(node, proposal: proposal)
        let actual = warm.measure(node, proposal: proposal)
        // Repeat unchanged to exercise certification as well as invalidation.
        let repeated = warm.measure(node, proposal: proposal)
        measurements(actual, expected)
        measurements(repeated, expected)
        let origin = CellPoint(x: -3, y: 7)
        let placed = warm.place(node, measured: actual, origin: origin)
        let reference = cold.place(node, measured: expected, origin: origin)
        #expect(
          placement(placed) == placement(reference),
          "generation=\(generation), proposal=\(proposal)")
      }
    }
    #expect(cache.metrics.hits > 0, "The differential test must actually exercise cache reuse")
  }

  private func measurements(_ actual: MeasuredNode, _ expected: MeasuredNode) {
    #expect(actual.identity == expected.identity)
    #expect(actual.measuredSize == expected.measuredSize)
    #expect(actual.proposal == expected.proposal)
    #expect(actual.childMeasurements.count == expected.childMeasurements.count)
    for (child, reference) in zip(actual.childMeasurements, expected.childMeasurements) {
      measurements(child, reference)
    }
  }

  private func placement(_ node: PlacedNode) -> [CellRect] {
    [node.bounds] + node.children.flatMap { placement($0) }
  }
}
