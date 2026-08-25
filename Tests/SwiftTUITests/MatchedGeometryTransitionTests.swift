import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// A matched-geometry swap composes with the pair's `.transition`s: the
/// arriving instance fades in along the matched path while the departing
/// instance's exit overlay travels the same path, so the two coincide and
/// cross-fade — SwiftUI positions a view in its removal transition onto the
/// new source. The match used to consume both transitions, cutting the
/// departing instance on the swap frame.
@MainActor
@Suite("Matched geometry with transitions")
struct MatchedGeometryTransitionTests {
  private static let key = MatchedGeometryKey(id: "hero")
  private static let surface = CellRect(origin: .zero, size: CellSize(width: 80, height: 8))
  private static let sourceBounds = CellRect(
    origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1))
  private static let destinationBounds = CellRect(
    origin: CellPoint(x: 40, y: 2), size: CellSize(width: 16, height: 3))
  /// `.frame` around `.center`: the anchor slides (4, 0.5) → (48, 3.5) and
  /// the size 8x1 → 16x3, so halfway is 12x2 centered on (26, 2).
  private static let halfwayBounds = CellRect(
    origin: CellPoint(x: 20, y: 1), size: CellSize(width: 12, height: 2))

  // MARK: - Controller-level fixture

  private struct Swap {
    let controller: AnimationController
    let sourceIdentity: Identity
    let destinationIdentity: Identity
    let placed: PlacedNode
    let start: MonotonicInstant
  }

  private enum Registration {
    case both, departingOnly, arrivingOnly, none

    var registersDeparting: Bool { self == .both || self == .departingOnly }
    var registersArriving: Bool { self == .both || self == .arrivingOnly }
  }

  /// Frame 1 places the source; frame 2 swaps the key to a destination under
  /// a 1 s linear animation, with `.opacity` registered per `registration`
  /// the way `TransitionRegistrationModifier` registers on resolve.
  private static func makeSwap(label: String, registration: Registration) -> Swap {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let root = testIdentity("MatchedTransition", label, "Root")
    let source = testIdentity("MatchedTransition", label, "Source")
    let destination = testIdentity("MatchedTransition", label, "Destination")
    let sourceNodeID = ViewNodeID(rawValue: 7_001)
    let destinationNodeID = ViewNodeID(rawValue: 7_002)
    let start = MonotonicInstant(offset: .seconds(400))

    func leaf(_ identity: Identity, nodeID: ViewNodeID) -> ResolvedNode {
      var node = ResolvedNode(
        viewNodeID: nodeID,
        identity: identity,
        kind: .view("Leaf"),
        children: [],
        layoutBehavior: .intrinsic,
        drawMetadata: DrawMetadata()
      )
      node.matchedGeometry = MatchedGeometryConfig(key: key)
      return node
    }

    // Every resolve runs the collection barrier, registered or not: it is
    // what snapshots the previous frame's registrations for removal lookup.
    controller.beginTransitionCollection()
    if registration.registersDeparting {
      controller.registerTransition(
        for: source, viewNodeID: sourceNodeID, transition: AnyTransition.opacity)
    }
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      ResolvedNode(
        identity: root, kind: .view("Root"), children: [leaf(source, nodeID: sourceNodeID)]),
      transaction: .init(),
      timestamp: start
    )
    controller.capturePlacedTree(
      PlacedNode(
        identity: root,
        bounds: surface,
        children: [
          PlacedNode(
            identity: source,
            bounds: sourceBounds,
            matchedGeometry: MatchedGeometryConfig(key: key)
          )
        ]
      )
    )

    controller.beginTransitionCollection()
    if registration.registersArriving {
      controller.registerTransition(
        for: destination, viewNodeID: destinationNodeID, transition: AnyTransition.opacity)
    }
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      ResolvedNode(
        identity: root, kind: .view("Root"),
        children: [leaf(destination, nodeID: destinationNodeID)]),
      transaction: transaction,
      timestamp: start
    )
    let placed = PlacedNode(
      identity: root,
      bounds: surface,
      children: [
        PlacedNode(
          identity: destination,
          bounds: destinationBounds,
          children: [
            // A coextensive decoration child (the `.background` shape).
            PlacedNode(
              identity: testIdentity("MatchedTransition", label, "Fill"),
              bounds: destinationBounds
            )
          ],
          matchedGeometry: MatchedGeometryConfig(key: key)
        )
      ]
    )
    return Swap(
      controller: controller,
      sourceIdentity: source,
      destinationIdentity: destination,
      placed: placed,
      start: start
    )
  }

  private static func node(_ identity: Identity, in tree: PlacedNode) -> PlacedNode? {
    tree.children.first { $0.identity == identity }
  }

  private static func arrivalOpacityKey(_ swap: Swap) -> AnimationKey {
    AnimationKey(identity: swap.destinationIdentity, slot: .opacity)
  }

  // MARK: - Both transitions: one path, two fades

  @Test("the departing instance keeps an exit overlay that travels the matched path")
  func departingOverlayTravelsTheMatchedPath() throws {
    let swap = Self.makeSwap(label: "Both", registration: .both)
    #expect(swap.controller.activeMatchedGeometryCount == 1)
    #expect(swap.controller.debugStateSnapshot().removingIdentities == [swap.sourceIdentity])

    let halfway = swap.start.advanced(by: .milliseconds(500))
    let snapshot = swap.controller.placedAnimationOverlaySnapshot(for: swap.placed, at: halfway)
    #expect(snapshot.removalOverlays.count == 1, "exactly one overlay for the counterpart")
    let overlay = try #require(snapshot.removalOverlays.first)
    let travel = try #require(overlay.matchedGeometryOffset)
    #expect(travel.identity == swap.sourceIdentity)
    #expect(travel.dx == Self.halfwayBounds.origin.x - Self.sourceBounds.origin.x)
    #expect(travel.dy == Self.halfwayBounds.origin.y - Self.sourceBounds.origin.y)
    #expect(travel.size == Self.halfwayBounds.size)
    #expect(abs((overlay.modifiers.opacity ?? -1) - 0.5) < 0.001, "\(overlay.modifiers)")
  }

  @Test("both instances render at the same interpolated rect with complementary opacity")
  func instancesCoincideAndCrossFadeOnBothApplyPaths() throws {
    let swap = Self.makeSwap(label: "Coincide", registration: .both)
    let halfway = swap.start.advanced(by: .milliseconds(500))

    // Worker-side entry point: snapshot, then apply the pure data.
    let snapshot = swap.controller.placedAnimationOverlaySnapshot(for: swap.placed, at: halfway)
    var workerTree = swap.placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &workerTree)

    let departing = try #require(Self.node(swap.sourceIdentity, in: workerTree))
    #expect(departing.isTransient, "the exit overlay stays display-only")
    #expect(departing.bounds == Self.halfwayBounds, "\(departing.bounds)")
    #expect(departing.drawMetadata.clipsToBounds, "a resized overlay clips like the live side")
    #expect(abs((departing.drawMetadata.baseStyle.explicitOpacity ?? -1) - 0.5) < 0.001)

    let arriving = try #require(Self.node(swap.destinationIdentity, in: workerTree))
    #expect(arriving.bounds == departing.bounds, "the pair coincides")
    let fill = try #require(arriving.children.first { $0.identity.path.hasSuffix("Fill") })
    #expect(fill.bounds == arriving.bounds, "coextensive decoration follows on the live side")
    // The arriving instance's fade is a resolved-slot property animation,
    // not a placed decoration: it is in flight on the controller.
    #expect(
      swap.controller.debugStateSnapshot().activeAnimationKeys.contains(
        Self.arrivalOpacityKey(swap)))

    // Main-actor entry point used by the older tests.
    var mainTree = swap.placed
    swap.controller.applyPlacedOverlays(to: &mainTree, at: halfway)
    let mainDeparting = try #require(Self.node(swap.sourceIdentity, in: mainTree))
    #expect(mainDeparting.bounds == departing.bounds)
    #expect(
      mainDeparting.drawMetadata.baseStyle.explicitOpacity
        == departing.drawMetadata.baseStyle.explicitOpacity)
  }

  @Test("the overlay starts exactly at the source rect and is gone once the curve ends")
  func overlayEndpoints() throws {
    let swap = Self.makeSwap(label: "Endpoints", registration: .both)

    var startTree = swap.placed
    swap.controller.applyPlacedOverlays(to: &startTree, at: swap.start)
    let atStart = try #require(Self.node(swap.sourceIdentity, in: startTree))
    #expect(atStart.bounds == Self.sourceBounds, "\(atStart.bounds)")
    #expect(atStart.drawMetadata.baseStyle.explicitOpacity == 1.0)

    let ended = swap.controller.placedAnimationOverlaySnapshot(
      for: swap.placed, at: swap.start.advanced(by: .milliseconds(1_500)))
    #expect(ended.removalOverlays.isEmpty)
  }

  // MARK: - One-sided registrations and the untransitioned swap

  @Test("a transition on the departing instance alone travels it without fading the arrival")
  func departingOnlyTravelsWithoutArrivalFade() throws {
    let swap = Self.makeSwap(label: "DepartingOnly", registration: .departingOnly)
    let state = swap.controller.debugStateSnapshot()
    #expect(state.removingIdentities == [swap.sourceIdentity])
    #expect(!state.activeAnimationKeys.contains(Self.arrivalOpacityKey(swap)))
    let snapshot = swap.controller.placedAnimationOverlaySnapshot(
      for: swap.placed, at: swap.start.advanced(by: .milliseconds(500)))
    #expect(snapshot.removalOverlays.first?.matchedGeometryOffset != nil)
  }

  @Test("a transition on the arriving instance alone fades it in with no exit overlay")
  func arrivingOnlyFadesInWithoutOverlay() throws {
    let swap = Self.makeSwap(label: "ArrivingOnly", registration: .arrivingOnly)
    let state = swap.controller.debugStateSnapshot()
    #expect(swap.controller.activeMatchedGeometryCount == 1)
    #expect(state.removingIdentities.isEmpty)
    #expect(state.activeAnimationKeys.contains(Self.arrivalOpacityKey(swap)))
  }

  @Test("an untransitioned swap retains no exit overlay and no fade")
  func untransitionedSwapRetainsNothingExtra() throws {
    let swap = Self.makeSwap(label: "None", registration: .none)
    let state = swap.controller.debugStateSnapshot()
    #expect(swap.controller.activeMatchedGeometryCount == 1)
    #expect(state.removingIdentities.isEmpty)
    #expect(!state.activeAnimationKeys.contains(Self.arrivalOpacityKey(swap)))
  }

  // MARK: - Raster through the real pipeline

  @Test("the raster cross-fades red to blue along the matched path")
  func rasterCrossFadesAlongTheMatchedPath() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .seconds(1))
    let rootIdentity = testIdentity("MatchedTransitionRaster")
    let proposal = ProposedSize(width: .finite(30), height: .finite(3))
    let t0 = MonotonicInstant.now()
    func context(_ transaction: TransactionSnapshot = .init()) -> ResolveContext {
      ResolveContext(identity: rootIdentity, transaction: transaction)
    }
    func backgrounds(_ frame: RenderSnapshot) throws -> [Color?] {
      try #require(frame.rasterSurface.cells.first).map { $0.style?.backgroundColor }
    }

    try withAnimationSinks(controller) {
      controller.register(animation)
      _ = renderer.render(
        MatchedTransitionRasterFixture(right: false),
        context: context(),
        proposal: proposal,
        frameInstant: t0
      )

      // The swap frame: the departing red box is still fully visible at the
      // source rect; the arriving blue box sits under it at opacity 0.
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      let swapFrame = renderer.render(
        MatchedTransitionRasterFixture(right: true),
        context: context(transaction),
        proposal: proposal,
        frameInstant: t0
      )
      #expect(controller.activeMatchedGeometryCount == 1)
      #expect(controller.debugStateSnapshot().removingIdentities.count == 1)
      let atSwap = try backgrounds(swapFrame)
      #expect(Array(atSwap[0..<4]) == Array(repeating: Color.red, count: 4), "\(atSwap)")
      #expect(!atSwap.contains(Color.blue), "\(atSwap)")

      // Halfway: source (0, w 4) to destination (10, w 4) puts the pair at
      // (5, w 4); both fills are translucent there, so the cells blend.
      let halfway = renderer.render(
        MatchedTransitionRasterFixture(right: true),
        context: context(),
        proposal: proposal,
        frameInstant: t0.advanced(by: .milliseconds(500))
      )
      let mid = try backgrounds(halfway)
      for column in 5..<9 {
        let color = mid[column]
        #expect(color != nil && color != Color.red && color != Color.blue, "column \(column): \(mid)")
      }
      #expect(!mid.contains(Color.red) && !mid.contains(Color.blue), "\(mid)")
      let untouched = mid.indices.filter { !(5..<9).contains($0) }
      #expect(untouched.allSatisfy { mid[$0] == nil }, "nothing paints off the path: \(mid)")

      // Past the curve: only the arriving blue box remains, at its slot.
      let ended = renderer.render(
        MatchedTransitionRasterFixture(right: true),
        context: context(),
        proposal: proposal,
        frameInstant: t0.advanced(by: .milliseconds(1_500))
      )
      let atEnd = try backgrounds(ended)
      #expect(Array(atEnd[10..<14]) == Array(repeating: Color.blue, count: 4), "\(atEnd)")
      #expect(!atEnd.contains(Color.red), "\(atEnd)")
    }
  }
}

// MARK: - Fixtures

@MainActor
private struct MatchedTransitionRasterFixture: View {
  let right: Bool

  var body: some View {
    HStack(spacing: 0) {
      if right {
        Text("").frame(width: 10)
        hero(color: .blue, label: "TWO")
      } else {
        hero(color: .red, label: "ONE")
        Text("").frame(width: 10)
      }
    }
  }

  private func hero(color: Color, label: String) -> some View {
    Text(label)
      .frame(width: 4, alignment: .leading)
      .background(color)
      .transition(.opacity)
      .matchedGeometryEffect(id: "hero")
  }
}
