import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage A0 pins for co-present adoption (plan 2026-08-25-003 §3.1): while a
/// source and an `isSource: false` instance share a key on one screen, the
/// non-source is laid out at its own slot but rendered at the source's frame
/// (per its `properties` and `anchor`), every frame, without an animation;
/// it stays interactive at the rendered frame; the retained layout baseline
/// stays un-adopted; and the exit overlay of a departing adopted instance is
/// frozen where it was drawn.
@MainActor
@Suite("Matched geometry co-present adoption")
struct MatchedGeometryAdoptionTests {
  private static let key = MatchedGeometryKey(id: "hero")
  private static let surface = CellRect(origin: .zero, size: CellSize(width: 80, height: 12))
  private static let sourceBounds = CellRect(
    origin: CellPoint(x: 2, y: 2), size: CellSize(width: 6, height: 1))
  private static let nonSourceBounds = CellRect(
    origin: CellPoint(x: 2, y: 6), size: CellSize(width: 6, height: 1))

  // MARK: - Controller-level fixture

  private struct Pair {
    let controller: AnimationController
    let animation: Animation
    let root: Identity
    let source: Identity
    let nonSource: Identity
    let nonSourceNodeID: ViewNodeID
    let placed: PlacedNode
    let start: MonotonicInstant
    let config: MatchedGeometryConfig
  }

  /// One frame with both instances present: the source at `sourceBounds`
  /// and the non-source laid out at `nonSourceBounds`.
  private static func makePair(
    label: String,
    sourceBounds: CellRect = sourceBounds,
    nonSourceBounds: CellRect = nonSourceBounds,
    properties: MatchedGeometryProperties = .frame,
    anchor: UnitPoint = .center,
    nonSourceTransition: AnyTransition? = nil
  ) -> Pair {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let root = testIdentity("MatchedAdoption", label, "Root")
    let source = testIdentity("MatchedAdoption", label, "Source")
    let nonSource = testIdentity("MatchedAdoption", label, "NonSource")
    let nonSourceNodeID = ViewNodeID(rawValue: 8_001)
    let start = MonotonicInstant(offset: .seconds(500))
    let config = MatchedGeometryConfig(
      key: key, isSource: false, properties: properties, anchor: anchor)

    controller.beginTransitionCollection()
    if let nonSourceTransition {
      controller.registerTransition(
        for: nonSource, viewNodeID: nonSourceNodeID, transition: nonSourceTransition)
    }
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      resolvedPair(
        root: root, source: source, nonSource: nonSource,
        nonSourceNodeID: nonSourceNodeID, config: config),
      transaction: .init(),
      timestamp: start
    )
    let placed = placedPair(
      root: root, source: source, sourceBounds: sourceBounds,
      nonSource: nonSource, nonSourceBounds: nonSourceBounds, config: config, label: label)
    controller.capturePlacedTree(placed)
    return Pair(
      controller: controller, animation: animation, root: root, source: source,
      nonSource: nonSource, nonSourceNodeID: nonSourceNodeID, placed: placed, start: start,
      config: config)
  }

  private static func resolvedPair(
    root: Identity,
    source: Identity?,
    nonSource: Identity?,
    nonSourceNodeID: ViewNodeID,
    config: MatchedGeometryConfig
  ) -> ResolvedNode {
    var children: [ResolvedNode] = []
    if let source {
      var node = ResolvedNode(identity: source, kind: .view("Leaf"))
      node.matchedGeometry = MatchedGeometryConfig(key: key)
      children.append(node)
    }
    if let nonSource {
      var node = ResolvedNode(
        viewNodeID: nonSourceNodeID, identity: nonSource, kind: .view("Leaf"),
        children: [], layoutBehavior: .intrinsic, drawMetadata: DrawMetadata())
      node.matchedGeometry = config
      children.append(node)
    }
    return ResolvedNode(identity: root, kind: .view("Root"), children: children)
  }

  private static func placedPair(
    root: Identity,
    source: Identity?,
    sourceBounds: CellRect,
    nonSource: Identity?,
    nonSourceBounds: CellRect,
    config: MatchedGeometryConfig,
    label: String
  ) -> PlacedNode {
    var children: [PlacedNode] = []
    if let source {
      children.append(
        PlacedNode(
          identity: source, bounds: sourceBounds,
          matchedGeometry: MatchedGeometryConfig(key: key)))
    }
    if let nonSource {
      children.append(
        PlacedNode(
          identity: nonSource,
          bounds: nonSourceBounds,
          children: [
            // A coextensive decoration child (the `.background` shape) and a
            // smaller content child.
            PlacedNode(
              identity: testIdentity("MatchedAdoption", label, "Fill"),
              bounds: nonSourceBounds
            ),
            PlacedNode(
              identity: testIdentity("MatchedAdoption", label, "Glyphs"),
              bounds: CellRect(origin: nonSourceBounds.origin, size: CellSize(width: 3, height: 1))
            ),
          ],
          matchedGeometry: config
        ))
    }
    return PlacedNode(identity: root, bounds: surface, children: children)
  }

  private static func node(_ identity: Identity, in tree: PlacedNode) -> PlacedNode? {
    if tree.identity == identity { return tree }
    for child in tree.children {
      if let found = node(identity, in: child) { return found }
    }
    return nil
  }

  /// The effective tree the raster tail would see for `pair` at `timestamp`.
  private static func effectiveTree(_ pair: Pair, at timestamp: MonotonicInstant) -> PlacedNode {
    let snapshot = pair.controller.placedAnimationOverlaySnapshot(for: pair.placed, at: timestamp)
    var tree = pair.placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    return tree
  }

  // MARK: - 1. Adopts every frame

  @Test("a co-present non-source renders at the source's rect every frame; the baseline stays put")
  func adoptsEveryFrame() throws {
    let pair = Self.makePair(label: "EveryFrame")

    for frame in 0..<3 {
      let at = pair.start.advanced(by: .milliseconds(100 * frame))
      let tree = Self.effectiveTree(pair, at: at)
      let adopted = try #require(Self.node(pair.nonSource, in: tree))
      #expect(adopted.bounds == Self.sourceBounds, "frame \(frame): \(adopted.bounds)")
      #expect(!adopted.isTransient, "an adopted node is a live node")
      // Nothing animates: adoption is a position, not a curve.
      #expect(pair.controller.activeMatchedGeometryCount == 0)

      // The retained baseline the controller captured is the un-adopted layout.
      let baseline = try #require(pair.controller.debugStateSnapshot().previousPlacedRoot)
      #expect(try #require(Self.node(pair.nonSource, in: baseline)).bounds == Self.nonSourceBounds)

      // Re-run the frame: the same trees, no transaction.
      pair.controller.beginTransitionCollection()
      pair.controller.finishTransitionCollection()
      pair.controller.processResolvedTree(
        Self.resolvedPair(
          root: pair.root, source: pair.source, nonSource: pair.nonSource,
          nonSourceNodeID: pair.nonSourceNodeID, config: pair.config),
        transaction: .init(),
        timestamp: at
      )
      pair.controller.capturePlacedTree(pair.placed)
    }
  }

  // MARK: - 2. `properties` and `anchor` govern the adoption

  @Test(".position adopts the source's anchor point and keeps the non-source's size")
  func positionAdoptsAnchorOnly() throws {
    let pair = Self.makePair(
      label: "Position",
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
      properties: .position
    )
    let adopted = try #require(
      Self.node(pair.nonSource, in: Self.effectiveTree(pair, at: pair.start)))
    // The source's center is (5, 2.5); a 4-wide box around it starts at 3.
    #expect(
      adopted.bounds
        == CellRect(origin: CellPoint(x: 3, y: 2), size: CellSize(width: 4, height: 1)),
      "\(adopted.bounds)")
    #expect(!adopted.drawMetadata.clipsToBounds, "a translation-only adoption does not clip")
  }

  @Test(".size adopts the source's size in place around the non-source's anchor")
  func sizeAdoptsSizeInPlace() throws {
    let pair = Self.makePair(
      label: "Size",
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
      properties: .size
    )
    let adopted = try #require(
      Self.node(pair.nonSource, in: Self.effectiveTree(pair, at: pair.start)))
    // The non-source's center (4, 6.5) stays put; a 6-wide box around it starts at 1.
    #expect(
      adopted.bounds
        == CellRect(origin: CellPoint(x: 1, y: 6), size: CellSize(width: 6, height: 1)),
      "\(adopted.bounds)")
    #expect(adopted.drawMetadata.clipsToBounds, "a resized adoption clips like a resized match")
  }

  @Test(".size with anchor .topLeading keeps the origin fixed")
  func sizeWithTopLeadingAnchorKeepsOrigin() throws {
    let pair = Self.makePair(
      label: "TopLeading",
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
      properties: .size,
      anchor: .topLeading
    )
    let adopted = try #require(
      Self.node(pair.nonSource, in: Self.effectiveTree(pair, at: pair.start)))
    #expect(
      adopted.bounds
        == CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 6, height: 1)),
      "\(adopted.bounds)")
  }

  @Test(".frame adopts both; coextensive decoration resizes and smaller content is clipped")
  func frameAdoptsBoundsAndClip() throws {
    let pair = Self.makePair(
      label: "Frame",
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1))
    )
    let adopted = try #require(
      Self.node(pair.nonSource, in: Self.effectiveTree(pair, at: pair.start)))
    #expect(adopted.bounds == Self.sourceBounds, "\(adopted.bounds)")
    #expect(adopted.drawMetadata.clipsToBounds)
    #expect(adopted.clipBounds == adopted.bounds, "semantics agree with paint")
    let fill = try #require(adopted.children.first { $0.identity.path.hasSuffix("Fill") })
    #expect(fill.bounds == adopted.bounds, "a coextensive decoration child resizes with the node")
    let glyphs = try #require(adopted.children.first { $0.identity.path.hasSuffix("Glyphs") })
    #expect(glyphs.bounds.size == CellSize(width: 3, height: 1), "smaller content keeps its layout")
    #expect(glyphs.bounds.origin == adopted.bounds.origin, "content translates with the node")
  }

  @Test("zero or several sources for a key adopt nothing")
  func adoptionRequiresExactlyOneSource() throws {
    let pair = Self.makePair(label: "TwoSources")
    // A second source for the same key in the same tree.
    var placed = pair.placed
    placed.children.append(
      PlacedNode(
        identity: testIdentity("MatchedAdoption", "TwoSources", "Source2"),
        bounds: CellRect(origin: CellPoint(x: 40, y: 2), size: CellSize(width: 6, height: 1)),
        matchedGeometry: MatchedGeometryConfig(key: Self.key)))
    let snapshot = pair.controller.placedAnimationOverlaySnapshot(for: placed, at: pair.start)
    var tree = placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    #expect(try #require(Self.node(pair.nonSource, in: tree)).bounds == Self.nonSourceBounds)

    // No source at all: the non-source stays at its own slot.
    var alone = pair.placed
    alone.children.removeAll { $0.identity == pair.source }
    let aloneSnapshot = pair.controller.placedAnimationOverlaySnapshot(for: alone, at: pair.start)
    var aloneTree = alone
    applyPlacedAnimationOverlaySnapshot(aloneSnapshot, to: &aloneTree)
    #expect(try #require(Self.node(pair.nonSource, in: aloneTree)).bounds == Self.nonSourceBounds)
  }

  // MARK: - 4. No spurious fly-in

  @Test("an unrelated animated write plans no matched animation on a co-present non-source")
  func unrelatedAnimatedWritePlansNothing() throws {
    let pair = Self.makePair(label: "NoFlyIn")
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(pair.animation.animationBox)
    pair.controller.beginTransitionCollection()
    pair.controller.finishTransitionCollection()
    pair.controller.processResolvedTree(
      Self.resolvedPair(
        root: pair.root, source: pair.source, nonSource: pair.nonSource,
        nonSourceNodeID: pair.nonSourceNodeID, config: pair.config),
      transaction: transaction,
      timestamp: pair.start
    )
    #expect(
      pair.controller.activeMatchedGeometryCount == 0,
      "a co-present non-source flew in from its source on an unrelated animated write")
    let adopted = try #require(
      Self.node(pair.nonSource, in: Self.effectiveTree(pair, at: pair.start)))
    #expect(adopted.bounds == Self.sourceBounds, "\(adopted.bounds)")
  }

  @Test("a non-source inserted beside an existing source adopts without flying in")
  func insertedNonSourceAdoptsWithoutFlyIn() throws {
    // Frame 1: the source alone. Frame 2: the non-source appears under an
    // animated transaction. It is co-present, so it is positioned, not flown.
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let root = testIdentity("MatchedAdoption", "Inserted", "Root")
    let source = testIdentity("MatchedAdoption", "Inserted", "Source")
    let nonSource = testIdentity("MatchedAdoption", "Inserted", "NonSource")
    let nodeID = ViewNodeID(rawValue: 8_002)
    let config = MatchedGeometryConfig(key: Self.key, isSource: false)
    let start = MonotonicInstant(offset: .seconds(510))

    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      Self.resolvedPair(
        root: root, source: source, nonSource: nil, nonSourceNodeID: nodeID, config: config),
      transaction: .init(), timestamp: start)
    controller.capturePlacedTree(
      Self.placedPair(
        root: root, source: source, sourceBounds: Self.sourceBounds, nonSource: nil,
        nonSourceBounds: Self.nonSourceBounds, config: config, label: "Inserted"))

    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      Self.resolvedPair(
        root: root, source: source, nonSource: nonSource, nonSourceNodeID: nodeID, config: config),
      transaction: transaction, timestamp: start)
    #expect(controller.activeMatchedGeometryCount == 0)

    let placed = Self.placedPair(
      root: root, source: source, sourceBounds: Self.sourceBounds, nonSource: nonSource,
      nonSourceBounds: Self.nonSourceBounds, config: config, label: "Inserted")
    let snapshot = controller.placedAnimationOverlaySnapshot(for: placed, at: start)
    var tree = placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    #expect(try #require(Self.node(nonSource, in: tree)).bounds == Self.sourceBounds)
  }

  // MARK: - 5. The drawn rect is the next frame's `from`

  @Test("when the source leaves, the non-source animates home from its adopted rect")
  func sourceLeavingAnimatesNonSourceHomeFromAdoptedRect() throws {
    let pair = Self.makePair(
      label: "SourceLeaves",
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
      properties: .position
    )
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(pair.animation.animationBox)
    pair.controller.beginTransitionCollection()
    pair.controller.finishTransitionCollection()
    pair.controller.processResolvedTree(
      Self.resolvedPair(
        root: pair.root, source: nil, nonSource: pair.nonSource,
        nonSourceNodeID: pair.nonSourceNodeID, config: pair.config),
      transaction: transaction,
      timestamp: pair.start
    )
    #expect(pair.controller.activeMatchedGeometryCount == 1)

    let alone = Self.placedPair(
      root: pair.root, source: nil, sourceBounds: Self.sourceBounds, nonSource: pair.nonSource,
      nonSourceBounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
      config: pair.config, label: "SourceLeaves")
    func bounds(at timestamp: MonotonicInstant) throws -> CellRect {
      let snapshot = pair.controller.placedAnimationOverlaySnapshot(for: alone, at: timestamp)
      var tree = alone
      applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
      return try #require(Self.node(pair.nonSource, in: tree)).bounds
    }
    // Progress 0 is exactly where it was drawn last frame: no jump.
    #expect(
      try bounds(at: pair.start)
        == CellRect(origin: CellPoint(x: 3, y: 2), size: CellSize(width: 4, height: 1)))
    #expect(
      try bounds(at: pair.start.advanced(by: .milliseconds(1_500)))
        == CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)))
  }

  @Test("a departing adopted non-source's exit overlay is frozen at its adopted rect and travels")
  func departingAdoptedNonSourceFreezesAtAdoptedRect() throws {
    let pair = Self.makePair(label: "Departs", nonSourceTransition: AnyTransition.opacity)
    let third = testIdentity("MatchedAdoption", "Departs", "Third")
    let thirdBounds = CellRect(origin: CellPoint(x: 40, y: 10), size: CellSize(width: 6, height: 1))

    // Frame 2: the pair leaves and a third instance takes the key, animated.
    var thirdNode = ResolvedNode(identity: third, kind: .view("Leaf"))
    thirdNode.matchedGeometry = MatchedGeometryConfig(key: Self.key)
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(pair.animation.animationBox)
    pair.controller.beginTransitionCollection()
    pair.controller.finishTransitionCollection()
    pair.controller.processResolvedTree(
      ResolvedNode(identity: pair.root, kind: .view("Root"), children: [thirdNode]),
      transaction: transaction,
      timestamp: pair.start
    )
    #expect(
      pair.controller.activeMatchedGeometryCount == 1, "the third instance receives the match")
    #expect(pair.controller.debugStateSnapshot().removingIdentities == [pair.nonSource])

    let placed = PlacedNode(
      identity: pair.root, bounds: Self.surface,
      children: [
        PlacedNode(
          identity: third, bounds: thirdBounds,
          matchedGeometry: MatchedGeometryConfig(key: Self.key))
      ])
    let snapshot = pair.controller.placedAnimationOverlaySnapshot(for: placed, at: pair.start)
    var tree = placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    let overlay = try #require(Self.node(pair.nonSource, in: tree))
    #expect(overlay.isTransient)
    #expect(
      overlay.bounds == Self.sourceBounds,
      "the exit overlay froze at the layout slot, not where the node was drawn: \(overlay.bounds)")

    // Halfway: the overlay travels the matched path toward the third instance.
    let halfway = pair.start.advanced(by: .milliseconds(500))
    let midSnapshot = pair.controller.placedAnimationOverlaySnapshot(for: placed, at: halfway)
    var midTree = placed
    applyPlacedAnimationOverlaySnapshot(midSnapshot, to: &midTree)
    let travelling = try #require(Self.node(pair.nonSource, in: midTree))
    let arriving = try #require(Self.node(third, in: midTree))
    #expect(
      travelling.bounds == arriving.bounds,
      "the pair coincides: \(travelling.bounds) vs \(arriving.bounds)")
    #expect(
      travelling.bounds.origin.x > Self.sourceBounds.origin.x
        && travelling.bounds.origin.x < thirdBounds.origin.x)
  }

  // MARK: - 8. Nested matched nodes keep the first-hit rule

  @Test("an inner matched node under an adopted outer node rides the outer translation")
  func nestedMatchedNodeRidesOuterAdoption() throws {
    let controller = AnimationController()
    let outerKey = MatchedGeometryKey(id: "outer")
    let innerKey = MatchedGeometryKey(id: "inner")
    let root = testIdentity("MatchedAdoption", "Nested", "Root")
    let outerSource = testIdentity("MatchedAdoption", "Nested", "OuterSource")
    let outer = testIdentity("MatchedAdoption", "Nested", "Outer")
    let inner = testIdentity("MatchedAdoption", "Nested", "Inner")
    let innerSource = testIdentity("MatchedAdoption", "Nested", "InnerSource")
    let start = MonotonicInstant(offset: .seconds(520))

    let placed = PlacedNode(
      identity: root, bounds: Self.surface,
      children: [
        PlacedNode(
          identity: outerSource,
          bounds: CellRect(origin: .zero, size: CellSize(width: 20, height: 3)),
          matchedGeometry: MatchedGeometryConfig(key: outerKey)),
        PlacedNode(
          identity: innerSource,
          bounds: CellRect(origin: CellPoint(x: 40, y: 0), size: CellSize(width: 4, height: 1)),
          matchedGeometry: MatchedGeometryConfig(key: innerKey)),
        PlacedNode(
          identity: outer,
          bounds: CellRect(origin: CellPoint(x: 0, y: 5), size: CellSize(width: 20, height: 3)),
          children: [
            PlacedNode(
              identity: inner,
              bounds: CellRect(origin: CellPoint(x: 2, y: 6), size: CellSize(width: 4, height: 1)),
              matchedGeometry: MatchedGeometryConfig(key: innerKey, isSource: false))
          ],
          matchedGeometry: MatchedGeometryConfig(key: outerKey, isSource: false)),
      ])
    let snapshot = controller.placedAnimationOverlaySnapshot(for: placed, at: start)
    var tree = placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    let adoptedOuter = try #require(Self.node(outer, in: tree))
    #expect(adoptedOuter.bounds == CellRect(origin: .zero, size: CellSize(width: 20, height: 3)))
    // Today's first-hit rule: the inner node's own adoption is dropped; it
    // moves with its adopted ancestor (a *Gap (narrowed)* in the register).
    let nested = try #require(Self.node(inner, in: tree))
    #expect(
      nested.bounds == CellRect(origin: CellPoint(x: 2, y: 1), size: CellSize(width: 4, height: 1)),
      "\(nested.bounds)")
  }

  // MARK: - 3, 6, 7. Semantics, incremental raster, and reduce motion through the pipeline

  @Test("an adopted button hit-tests and focuses at the drawn rect, above the source")
  func adoptedNodeSemanticsFollowTheDrawnRect() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("MatchedAdoptionSemantics")
    let frame = renderer.render(
      AdoptionSemanticsFixture(),
      context: ResolveContext(identity: rootIdentity),
      proposal: ProposedSize(width: .finite(30), height: .finite(6))
    )
    let regions = frame.semanticSnapshot.interactionRegions
    let source = try #require(regions.first { $0.identity.path.contains("SourceButton") })
    let badge = try #require(regions.first { $0.identity.path.contains("BadgeButton") })
    #expect(source.rect.origin.y == 0, "\(source.rect)")
    // The matched node is the 8-wide `.frame`; each button keeps its own
    // intrinsic width inside it, so compare where the regions start.
    #expect(
      badge.rect.origin == source.rect.origin,
      "the badge is interactive where it is drawn: \(badge.rect) vs \(source.rect)")
    #expect(badge.rect.size.height == source.rect.size.height)

    // Z-order: the later sibling (the badge, drawn over the source) wins the hit.
    let point = PointerLocation.cellFallback(
      CellPoint(x: source.rect.origin.x + 1, y: source.rect.origin.y))
    let hit = regions.filter { $0.contains(point) }.max { $0.hitTestOrder < $1.hitTestOrder }
    #expect(try #require(hit).identity == badge.identity, "\(String(describing: hit?.identity))")
  }

  @Test("reduce motion leaves adoption on")
  func reduceMotionKeepsAdoption() throws {
    let renderer = DefaultRenderer()
    let rootIdentity = testIdentity("MatchedAdoptionReduceMotion")
    var context = ResolveContext(identity: rootIdentity)
    context.environmentValues.accessibilityReduceMotion = true
    let frame = renderer.render(
      AdoptionSemanticsFixture(),
      context: context,
      proposal: ProposedSize(width: .finite(30), height: .finite(6))
    )
    let regions = frame.semanticSnapshot.interactionRegions
    let source = try #require(regions.first { $0.identity.path.contains("SourceButton") })
    let badge = try #require(regions.first { $0.identity.path.contains("BadgeButton") })
    #expect(badge.rect.origin == source.rect.origin, "\(badge.rect) vs \(source.rect)")
  }

  @Test("a steady co-present pair keeps unrelated text changes on the incremental raster path")
  func steadyAdoptionRastersIncrementally() async throws {
    let harness = try AnimatorRuntimeHarness(size: .init(width: 40, height: 8)) {
      AdoptionCounterFixture()
    }
    defer { harness.shutdown() }
    #expect(harness.frame.contains("count 0"))
    // Two steady frames with the pair on screen, then one text change elsewhere.
    try harness.clickText("bump")
    try harness.clickText("bump")
    #expect(harness.frame.contains("count 2"), "\(harness.frame)")

    let records = harness.frameRecords
    let last = try #require(records.last)
    #expect(
      last.rasterPath == Rasterizer.RasterPath.incremental.rawValue,
      "the text-change frame did not raster incrementally: \(last.rasterPath) \(last.rasterReuseBarriers)"
    )
    let paths = records.map(\.rasterPath)
    #expect(
      !paths.contains(Rasterizer.RasterPath.incrementalRepaired.rawValue),
      "the F06 oracle repaired an under-damaged frame: \(paths)")
    // And the badge is still drawn on the source.
    let lines = harness.frame.split(separator: "\n").map(String.init)
    #expect(lines.first?.contains("BADGE") == true, "\(harness.frame)")
    #expect(!lines.dropFirst(2).contains { $0.contains("BADGE") }, "\(harness.frame)")
  }
}

// MARK: - Fixtures

@MainActor
private struct AdoptionSemanticsFixture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("SOURCE") {}
        .buttonStyle(.plain)
        .frame(width: 8, alignment: .leading)
        .matchedGeometryEffect(id: "hero")
        .id("SourceButton")
      Text("").frame(height: 2)
      Button("BADGE") {}
        .buttonStyle(.plain)
        .frame(width: 8, alignment: .leading)
        .matchedGeometryEffect(id: "hero", isSource: false)
        .id("BadgeButton")
    }
  }
}

@MainActor
private struct AdoptionCounterFixture: View {
  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text("SOURCE")
        .frame(width: 8, alignment: .leading)
        .matchedGeometryEffect(id: "hero")
      Text("")
      Text("BADGE")
        .frame(width: 8, alignment: .leading)
        .matchedGeometryEffect(id: "hero", isSource: false)
      Text("")
      // The counter's state lives below the root so the click invalidates a
      // subtree, the shape the incremental rasterizer serves.
      AdoptionCounterPane()
    }
  }
}

@MainActor
private struct AdoptionCounterPane: View {
  @State private var count = 0

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Button("bump") { count += 1 }
      Text("count \(count)")
    }
  }
}
