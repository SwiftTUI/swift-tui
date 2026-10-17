import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

// STUI-591 (oversize alignment), STUI-595 (border insets), STUI-613 (rigid
// spacers), and the October layout repairs motivate these composition probes.
// These assert independent geometry, rather than comparing two engine instances.
@Suite("Adversarial set A: layout composition")
struct AdversarialSetALayoutCompositionTests {
  @Test func setA176OddOverflowCentersInsideTranslatedFrame() {
    let node = wrap(.frame(width: 4, height: 3, alignment: .center), [leaf(1, 7, 6)])
    let placed = place(node, origin: .init(x: -11, y: 9))
    #expect(placed.bounds.size == .init(width: 4, height: 3))
    #expect(placed.children[0].bounds.origin == .init(x: -12, y: 8))
  }

  @Test func setA177TrailingOverflowSurvivesAsymmetricPadding() {
    let content = wrap(.padding(.init(top: 1, leading: 2)), [leaf(1, 7, 5)], id: 2)
    let node = wrap(.frame(width: 4, height: 3, alignment: .bottomTrailing), [content])
    let placed = place(node)
    #expect(placed.children[0].children[0].bounds.origin == .init(x: -3, y: -2))
    #expect(placed.children[0].children[0].bounds.size == .init(width: 7, height: 5))
  }

  @Test func setA178IntermediateGuideWinsOverLeafGuide() {
    var content = leaf(1, 3, 1)
    content.layoutMetadata = horizontalGuide(9)
    var padding = wrap(.padding(.init(leading: 2)), [content], id: 2)
    padding.layoutMetadata = horizontalGuide(-4)
    let node = wrap(.frame(width: 10, height: 1, alignment: .leading), [padding])
    #expect(place(node).children[0].bounds.origin.x == 4)
  }

  @Test func setA179DecorationPropagatesSecondPrimaryGuide() {
    var primary = leaf(1, 3, 1)
    primary.layoutMetadata = horizontalGuide(2)
    var adornment = leaf(2, 9, 1)
    adornment.layoutMetadata = horizontalGuide(-20)
    let decorated = wrap(
      .decoration(primaryIndex: 1, alignment: .leading), [adornment, primary], id: 3)
    let framed = wrap(.frame(width: 10, height: 1, alignment: .leading), [decorated])
    #expect(place(framed).children[0].bounds.origin.x == -2)
  }

  @Test func setA180PaintOffsetDoesNotMovePropagatedLayoutGuide() {
    var content = leaf(1, 3, 1)
    content.layoutMetadata = horizontalGuide(2)
    let offset = wrap(.offset(x: 7, y: -3), [content], id: 2)
    let framed = wrap(.frame(width: 10, height: 2, alignment: .topLeading), [offset])
    let placed = place(framed)
    #expect(placed.children[0].bounds.origin.x == -2)
    #expect(placed.children[0].children[0].bounds.origin == .init(x: 5, y: -3))
  }

  @Test func setA181PositionUsesTranslatedParentCoordinates() {
    let node = wrap(.position(x: 4, y: 6), [leaf(1, 6, 4)])
    let placed = place(node, proposal: .init(width: 20, height: 12), origin: .init(x: -9, y: 7))
    #expect(placed.bounds.size == .init(width: 20, height: 12))
    #expect(placed.children[0].bounds.origin == .init(x: -8, y: 11))
  }

  @Test func setA182NestedOffsetsCancelWithoutChangingSiblingAllocation() {
    let inner = wrap(.offset(x: 13, y: -8), [leaf(1, 4, 2)], id: 2)
    let outer = wrap(.offset(x: -13, y: 8), [inner], id: 3)
    let node = stack([outer, leaf(4, 3, 2)], axis: .horizontal, spacing: 1)
    let placed = place(node)
    #expect(placed.bounds.size == .init(width: 8, height: 2))
    #expect(placed.children[0].children[0].children[0].bounds.origin == .zero)
    #expect(placed.children[1].bounds.origin.x == 5)
  }

  @Test func setA183SafeAreaPrimaryGuideMatchesItsPlacedChild() {
    var primary = leaf(1, 6, 2)
    primary.layoutMetadata = horizontalGuide(1)
    let inset = wrap(
      .safeAreaInset(
        edge: .leading, alignment: .topLeading, spacing: 2, safeArea: .init(leading: 1)),
      [primary, leaf(2, 3, 2)])
    let engine = LayoutEngine()
    let measured = engine.measure(inset)
    let placed = engine.place(inset, measured: measured, origin: .zero)
    let dimensions = engine.viewDimensions(for: inset, measured: measured)
    #expect(placed.children[0].bounds.origin.x == 4)
    #expect(dimensions[HorizontalAlignment.leading] == placed.children[0].bounds.origin.x + 1)
  }

  @Test func setA184BottomInsetDoesNotShiftPrimaryTopGuide() {
    var primary = leaf(1, 4, 3)
    primary.layoutMetadata = LayoutMetadata().settingVerticalAlignmentGuide(
      .top, debugName: "top", computeValue: { _ in -2 })
    let node = wrap(
      .safeAreaInset(edge: .bottom, alignment: .leading, spacing: 1, safeArea: .init(bottom: 1)),
      [primary, leaf(2, 4, 2)])
    let engine = LayoutEngine()
    let measured = engine.measure(node)
    #expect(engine.viewDimensions(for: node, measured: measured)[VerticalAlignment.top] == -2)
    #expect(engine.place(node, measured: measured, origin: .zero).children[0].bounds.origin.y == 0)
  }

  @Test func setA185InsetInsideReservedSafeAreaDoesNotShrinkPrimary() {
    let node = wrap(
      .safeAreaInset(edge: .top, alignment: .leading, spacing: 1, safeArea: .init(top: 4)),
      [leaf(1, 8, 3), leaf(2, 2, 2)])
    let placed = place(node)
    #expect(placed.bounds.size == .init(width: 8, height: 3))
    #expect(placed.children[0].bounds.origin == .zero)
    #expect(placed.children[1].bounds.origin.y == -4)
  }

  @Test func setA186IgnoringEmptySafeAreaRemainsIntrinsicUnderLargeProposal() {
    let node = wrap(.safeAreaIgnoring(.init(), fillsProposal: false), [leaf(1, 3, 2)])
    #expect(
      place(node, proposal: .init(width: 90, height: 60)).bounds.size == .init(width: 3, height: 2))
  }

  @Test func setA187IgnoringOnlyHorizontalInsetsLeavesHeightIntrinsic() {
    let node = wrap(
      .safeAreaIgnoring(.init(leading: 2, trailing: 3), fillsProposal: false), [leaf(1, 3, 2)])
    let placed = place(node, proposal: .init(width: 10, height: 20))
    #expect(placed.bounds.size == .init(width: 10, height: 2))
    #expect(
      placed.children[0].bounds
        == .init(origin: .init(x: -2, y: 0), size: .init(width: 15, height: 2)))
  }

  @Test func setA188LargeDecorationCannotEnlargePrimaryLayout() {
    let node = wrap(
      .decoration(primaryIndex: 0, alignment: .center), [leaf(1, 3, 2), leaf(2, 10, 9)])
    let placed = place(node)
    #expect(placed.bounds.size == .init(width: 3, height: 2))
    #expect(placed.children[0].bounds.origin == .zero)
    #expect(placed.children[1].bounds.origin == .init(x: -3, y: -3))
  }

  @Test func setA189DecorationUsesSecondPrimaryForUnspecifiedAxis() {
    let node = wrap(
      .decoration(primaryIndex: 1, alignment: .bottomTrailing), [leaf(1, 10, 9), leaf(2, 3, 2)])
    let placed = place(node, proposal: .init(width: 20, height: .unspecified))
    #expect(placed.bounds.size == .init(width: 3, height: 2))
    #expect(placed.children[1].bounds.origin == .zero)
    #expect(placed.children[0].bounds.origin == .init(x: -7, y: -7))
  }

  @Test func setA190ViewThatFitsAcceptsExactBoundaryBeforeFallback() {
    expectChoice(
      [leaf(1, 7, 3), leaf(2, 2, 1)], axes: [.horizontal, .vertical],
      proposal: .init(width: 7, height: 3), selected: 1)
  }

  @Test func setA191HorizontalFitDoesNotRejectTallCandidate() {
    expectChoice(
      [leaf(1, 4, 30), leaf(2, 2, 1)], axes: .horizontal, proposal: .init(width: 4, height: 2),
      selected: 1)
  }

  @Test func setA192VerticalFitDoesNotRejectWideCandidate() {
    expectChoice(
      [leaf(1, 30, 2), leaf(2, 1, 1)], axes: .vertical, proposal: .init(width: 2, height: 2),
      selected: 1)
  }

  @Test func setA193ViewThatFitsFallsBackToLastWithoutClippingItsSize() {
    let node = wrap(.viewThatFits([.horizontal, .vertical]), [leaf(1, 8, 6), leaf(2, 7, 5)])
    let placed = place(node, proposal: .init(width: 2, height: 1))
    #expect(placed.children.map(\.identity) == [leaf(2, 7, 5).identity])
    #expect(placed.bounds.size == .init(width: 7, height: 5))
  }

  @Test func setA194ViewThatFitsReconsidersAfterProposalShrinkAndGrowth() {
    let node = wrap(.viewThatFits(.horizontal), [leaf(1, 9, 1), leaf(2, 4, 1), leaf(3, 1, 1)])
    let engine = LayoutEngine(cache: MeasurementCache())
    for (width, selected) in [(10, 1), (5, 2), (0, 3), (10, 1)] {
      let measured = engine.measure(node, proposal: .init(width: .finite(width), height: 2))
      let placed = engine.place(node, measured: measured, origin: .zero)
      #expect(placed.children.map(\.identity) == [testIdentity("SetAComposition", "\(selected)")])
    }
  }

  @Test func setA195SpacerMinimumSurvivesTwoTransparentWrappers() {
    var spacer = leaf(1, 7, 0)
    spacer.kind = .view("Spacer")
    spacer.drawMetadata.leafStackAxis = .horizontal
    spacer.layoutMetadata = .init()
    let wrapped = wrap(.offset(x: 0, y: 0), [wrap(.padding(.init()), [spacer], id: 2)], id: 3)
    let node = stack([wrapped, leaf(4, 2, 1)], axis: .horizontal, spacing: 1)
    let placed = place(node, proposal: .init(width: 5, height: 1))
    #expect(placed.children[0].bounds.size.width >= 7)
    #expect(placed.bounds.size.width >= 10)
  }

  @Test func setA196EmptyStackDoesNotChargePhantomSpacing() {
    for axis: Axis in [.horizontal, .vertical] {
      let node = stack([], axis: axis, spacing: 9)
      #expect(place(node, proposal: .init(width: 12, height: 8)).bounds.size == .zero)
    }
  }

  @Test func setA197FixedSizeSpacerRemainsRigidInsidePadding() {
    var spacer = leaf(1, 3, 0)
    spacer.kind = .view("Spacer")
    spacer.drawMetadata.leafStackAxis = .horizontal
    spacer.layoutMetadata = .init(fixedSizeHorizontal: true)
    let padded = wrap(.padding(.init(leading: 2, trailing: 1)), [spacer], id: 2)
    let node = stack([padded, leaf(3, 2, 1)], axis: .horizontal, spacing: 1)
    let placed = place(node, proposal: .init(width: 30, height: 1))
    #expect(placed.children[0].bounds.size.width == 6)
    #expect(placed.bounds.size.width == 9)
  }

  @Test func setA198OutsetBorderReservesOnlyEnabledEdges() {
    let bordered = wrap(
      .border(
        .single, placement: .outset, foreground: nil, background: nil,
        blend: nil, blendPhase: 0, sides: [.top, .trailing]), [leaf(1, 5, 2)])
    let placed = place(bordered, origin: .init(x: 4, y: -7))
    #expect(placed.bounds.size == .init(width: 6, height: 3))
    #expect(
      placed.children[0].bounds
        == .init(origin: .init(x: 4, y: -6), size: .init(width: 5, height: 2)))
  }

  @Test func setA199ZeroSizedChildStillHasExactlyOneGapOnEachSide() {
    let node = stack([leaf(1, 2, 1), leaf(2, 0, 0), leaf(3, 3, 1)], axis: .horizontal, spacing: 2)
    let placed = place(node)
    #expect(placed.bounds.size.width == 9)
    #expect(placed.children.map { $0.bounds.origin.x } == [0, 4, 6])
  }

  @Test func setA200NestedStacksPreserveAxisTransposeGeometry() {
    let horizontal = stack([leaf(1, 3, 2), leaf(2, 5, 4)], axis: .horizontal, spacing: 2, id: 3)
    let vertical = stack([leaf(1, 2, 3), leaf(2, 4, 5)], axis: .vertical, spacing: 2, id: 3)
    let a = place(wrap(.padding(.init(top: 1, leading: 3, bottom: 2, trailing: 4)), [horizontal]))
    let b = place(wrap(.padding(.init(top: 3, leading: 1, bottom: 4, trailing: 2)), [vertical]))
    #expect(a.bounds.size.width == b.bounds.size.height)
    #expect(a.bounds.size.height == b.bounds.size.width)
    for (left, right) in zip(a.children[0].children, b.children[0].children) {
      #expect(left.bounds.origin.x == right.bounds.origin.y)
      #expect(left.bounds.origin.y == right.bounds.origin.x)
    }
  }

  private func leaf(_ id: Int, _ width: Int, _ height: Int) -> ResolvedNode {
    .init(
      viewNodeID: .init(rawValue: UInt64(id)), identity: testIdentity("SetAComposition", "\(id)"),
      kind: .view("Probe"),
      layoutMetadata: .init(fixedSizeHorizontal: true, fixedSizeVertical: true),
      intrinsicSize: .init(width: width, height: height))
  }

  private func wrap(_ behavior: LayoutBehavior, _ children: [ResolvedNode], id: Int = 90)
    -> ResolvedNode
  {
    .init(
      viewNodeID: .init(rawValue: UInt64(id)), identity: testIdentity("SetAComposition", "\(id)"),
      kind: .view("Wrapper"), children: children, layoutBehavior: behavior)
  }

  private func stack(_ children: [ResolvedNode], axis: Axis, spacing: Int, id: Int = 90)
    -> ResolvedNode
  {
    wrap(
      .stack(axis: axis, spacing: spacing, horizontalAlignment: .leading, verticalAlignment: .top),
      children, id: id)
  }

  private func place(
    _ node: ResolvedNode, proposal: ProposedSize = .unspecified, origin: CellPoint = .zero
  ) -> PlacedNode {
    let engine = LayoutEngine()
    return engine.place(node, measured: engine.measure(node, proposal: proposal), origin: origin)
  }

  private func horizontalGuide(_ value: Int) -> LayoutMetadata {
    LayoutMetadata().settingHorizontalAlignmentGuide(
      .leading, debugName: "leading", computeValue: { _ in value })
  }

  private func expectChoice(
    _ children: [ResolvedNode], axes: AxisSet, proposal: ProposedSize, selected: Int
  ) {
    let placed = place(wrap(.viewThatFits(axes), children), proposal: proposal)
    #expect(placed.children.map(\.identity) == [testIdentity("SetAComposition", "\(selected)")])
  }
}
