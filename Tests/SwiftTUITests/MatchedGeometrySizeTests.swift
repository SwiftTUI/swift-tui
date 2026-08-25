import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

/// Stage M0 pins for matched geometry (plan 2026-08-25-002 §5): the
/// existing translation path sampled at intermediate progress on both apply
/// entry points, and the `properties:`/`anchor:` size interpolation by
/// bounds and clip.
@MainActor
@Suite("Matched geometry size and anchor")
struct MatchedGeometrySizeTests {
  private static let key = MatchedGeometryKey(id: "hero")

  // MARK: - Controller-level fixtures

  private struct Swap {
    let controller: AnimationController
    let sourceIdentity: Identity
    let destinationIdentity: Identity
    let placed: PlacedNode
    let start: MonotonicInstant
  }

  /// Frame 1 places the source at `sourceBounds`; frame 2 swaps the key to a
  /// destination placed at `destinationBounds` under a 1 s linear animation.
  private static func makeSwap(
    label: String,
    sourceBounds: CellRect,
    destinationBounds: CellRect,
    properties: MatchedGeometryProperties = .frame,
    anchor: UnitPoint = .center
  ) -> Swap {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let root = testIdentity("MatchedSize", label, "Root")
    let source = testIdentity("MatchedSize", label, "Source")
    let destination = testIdentity("MatchedSize", label, "Destination")
    let start = MonotonicInstant(offset: .seconds(300))

    var sourceNode = ResolvedNode(identity: source, kind: .view("Leaf"))
    sourceNode.matchedGeometry = MatchedGeometryConfig(key: key)
    controller.processResolvedTree(
      ResolvedNode(identity: root, kind: .view("Root"), children: [sourceNode]),
      transaction: .init(),
      timestamp: start
    )
    controller.capturePlacedTree(
      PlacedNode(
        identity: root,
        bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 8)),
        children: [
          PlacedNode(
            identity: source,
            bounds: sourceBounds,
            matchedGeometry: MatchedGeometryConfig(key: key)
          )
        ]
      )
    )

    var destinationNode = ResolvedNode(identity: destination, kind: .view("Leaf"))
    let config = MatchedGeometryConfig(key: key, properties: properties, anchor: anchor)
    destinationNode.matchedGeometry = config
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      ResolvedNode(identity: root, kind: .view("Root"), children: [destinationNode]),
      transaction: transaction,
      timestamp: start
    )
    let placed = PlacedNode(
      identity: root,
      bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 8)),
      children: [
        PlacedNode(
          identity: destination,
          bounds: destinationBounds,
          children: [
            // A coextensive decoration child (the `.background` shape) and a
            // smaller content child.
            PlacedNode(
              identity: testIdentity("MatchedSize", label, "Fill"),
              bounds: destinationBounds
            ),
            PlacedNode(
              identity: testIdentity("MatchedSize", label, "Glyphs"),
              bounds: CellRect(
                origin: destinationBounds.origin,
                size: CellSize(width: 3, height: 1)
              )
            ),
          ],
          matchedGeometry: config
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

  private static func destination(in tree: PlacedNode, _ swap: Swap) -> PlacedNode? {
    tree.children.first { $0.identity == swap.destinationIdentity }
  }

  // MARK: - Existing translation path, both apply entry points

  @Test("intermediate progress lands strictly between source and destination on both apply paths")
  func translationSamplesBetweenEndpointsOnBothPaths() throws {
    let swap = Self.makeSwap(
      label: "Translate",
      sourceBounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1)),
      destinationBounds: CellRect(
        origin: CellPoint(x: 40, y: 0), size: CellSize(width: 8, height: 1))
    )
    let halfway = swap.start.advanced(by: .milliseconds(500))

    // Worker-side entry point: snapshot, then apply the pure data.
    let snapshot = swap.controller.placedAnimationOverlaySnapshot(for: swap.placed, at: halfway)
    var workerTree = swap.placed
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &workerTree)
    let workerNode = try #require(Self.destination(in: workerTree, swap))
    #expect(
      workerNode.bounds.origin.x > 0 && workerNode.bounds.origin.x < 40, "\(workerNode.bounds)")
    #expect(workerNode.bounds.origin.x == 20)

    // Main-actor entry point used by the older tests.
    var mainTree = swap.placed
    swap.controller.applyPlacedOverlays(to: &mainTree, at: halfway)
    let mainNode = try #require(Self.destination(in: mainTree, swap))
    #expect(mainNode.bounds == workerNode.bounds)
  }

  // MARK: - Size interpolation

  @Test(".frame interpolates size between the source and destination widths")
  func frameInterpolatesSize() throws {
    let swap = Self.makeSwap(
      label: "Frame",
      sourceBounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1)),
      destinationBounds: CellRect(
        origin: CellPoint(x: 20, y: 2), size: CellSize(width: 16, height: 3))
    )
    var tree = swap.placed
    swap.controller.applyPlacedOverlays(to: &tree, at: swap.start.advanced(by: .milliseconds(500)))
    let node = try #require(Self.destination(in: tree, swap))

    #expect(node.bounds.size == CellSize(width: 12, height: 2), "\(node.bounds)")
    // Center anchor: the midpoint slides from (4, 0.5) to (28, 3.5).
    #expect(node.bounds.origin == CellPoint(x: 10, y: 1), "\(node.bounds)")
    #expect(node.drawMetadata.clipsToBounds, "a resized node clips to its interpolated rect")
    #expect(node.clipBounds == node.bounds, "semantics agree with paint")

    let fill = try #require(node.children.first { $0.identity.path.hasSuffix("Fill") })
    #expect(fill.bounds == node.bounds, "a coextensive decoration child resizes with the node")
    let glyphs = try #require(node.children.first { $0.identity.path.hasSuffix("Glyphs") })
    #expect(glyphs.bounds.size == CellSize(width: 3, height: 1), "smaller content keeps its layout")
    #expect(glyphs.bounds.origin == node.bounds.origin, "content translates with the node")
  }

  @Test(".frame renders exactly at the source rect at progress 0 and the destination at 1")
  func frameEndpointsAreExact() throws {
    let source = CellRect(origin: CellPoint(x: 3, y: 1), size: CellSize(width: 5, height: 1))
    let destination = CellRect(origin: CellPoint(x: 30, y: 4), size: CellSize(width: 14, height: 3))
    let swap = Self.makeSwap(
      label: "Endpoints", sourceBounds: source, destinationBounds: destination)

    var startTree = swap.placed
    swap.controller.applyPlacedOverlays(to: &startTree, at: swap.start)
    #expect(try #require(Self.destination(in: startTree, swap)).bounds == source)

    var endTree = swap.placed
    swap.controller.applyPlacedOverlays(
      to: &endTree, at: swap.start.advanced(by: .milliseconds(1_500)))
    #expect(try #require(Self.destination(in: endTree, swap)).bounds == destination)
  }

  @Test(".position never changes the size")
  func positionOnlyKeepsDestinationSize() throws {
    let swap = Self.makeSwap(
      label: "Position",
      sourceBounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1)),
      destinationBounds: CellRect(
        origin: CellPoint(x: 20, y: 0), size: CellSize(width: 16, height: 1)),
      properties: .position
    )
    var tree = swap.placed
    swap.controller.applyPlacedOverlays(to: &tree, at: swap.start.advanced(by: .milliseconds(500)))
    let node = try #require(Self.destination(in: tree, swap))
    #expect(node.bounds.size == CellSize(width: 16, height: 1), "\(node.bounds)")
    // The center slides from 4 to 28: 16 at the midpoint, so the origin is 8.
    #expect(node.bounds.origin.x == 8, "\(node.bounds)")
    #expect(!node.drawMetadata.clipsToBounds)
  }

  @Test(".size never moves the anchor point")
  func sizeOnlyResizesAroundAnchor() throws {
    let swap = Self.makeSwap(
      label: "Size",
      sourceBounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1)),
      destinationBounds: CellRect(
        origin: CellPoint(x: 20, y: 0), size: CellSize(width: 16, height: 1)),
      properties: .size
    )
    var tree = swap.placed
    swap.controller.applyPlacedOverlays(to: &tree, at: swap.start.advanced(by: .milliseconds(500)))
    let node = try #require(Self.destination(in: tree, swap))
    #expect(node.bounds.size.width == 12, "\(node.bounds)")
    // The destination's center (28) stays put: origin 22.
    #expect(node.bounds.origin.x == 22, "\(node.bounds)")
  }

  @Test("anchor: .topLeading keeps the origin fixed while the size interpolates")
  func topLeadingAnchorKeepsOrigin() throws {
    let swap = Self.makeSwap(
      label: "TopLeading",
      sourceBounds: CellRect(origin: CellPoint(x: 0, y: 0), size: CellSize(width: 8, height: 1)),
      destinationBounds: CellRect(
        origin: CellPoint(x: 20, y: 0), size: CellSize(width: 16, height: 1)),
      properties: .size,
      anchor: .topLeading
    )
    var tree = swap.placed
    swap.controller.applyPlacedOverlays(to: &tree, at: swap.start.advanced(by: .milliseconds(500)))
    let node = try #require(Self.destination(in: tree, swap))
    #expect(node.bounds.origin == CellPoint(x: 20, y: 0), "\(node.bounds)")
    #expect(node.bounds.size.width == 12, "\(node.bounds)")
  }

  // MARK: - Raster and semantics through the real pipeline

  @Test(
    "the raster clips a growing matched node to the interpolated rect and the background fills it")
  func rasterClipsToInterpolatedRect() throws {
    let renderer = DefaultRenderer()
    let controller = renderer.internalAnimationController
    let animation = Animation.linear(duration: .seconds(1))
    let rootIdentity = testIdentity("MatchedSizeRaster")
    let proposal = ProposedSize(width: .finite(30), height: .finite(3))
    let t0 = MonotonicInstant.now()

    try withAnimationSinks(controller) {
      controller.register(animation)
      _ = renderer.render(
        MatchedRasterFixture(wide: false),
        context: ResolveContext(identity: rootIdentity),
        proposal: proposal,
        frameInstant: t0
      )
      var transaction = TransactionSnapshot()
      transaction.animationRequest = .animate(animation.animationBox)
      _ = renderer.render(
        MatchedRasterFixture(wide: true),
        context: ResolveContext(identity: rootIdentity, transaction: transaction),
        proposal: proposal,
        frameInstant: t0
      )
      #expect(controller.activeMatchedGeometryCount == 1)

      let halfway = renderer.render(
        MatchedRasterFixture(wide: true),
        context: ResolveContext(identity: rootIdentity),
        proposal: proposal,
        frameInstant: t0.advanced(by: .milliseconds(500))
      )
      // Source rect (0, w 2) to destination (10, w 8), both two rows tall:
      // halfway is (5, w 5). The semantics carry the interpolated rect.
      let region = try #require(
        halfway.semanticSnapshot.interactionRegions.first { region in
          region.identity.path.contains("MatchedButton")
        }
      )
      let rect = region.rect
      #expect(rect == CellRect(origin: CellPoint(x: 5, y: 0), size: CellSize(width: 5, height: 2)))

      // The plain button style keeps a leading marker cell, so the label's
      // glyphs start one column into the rect and run past its trailing edge;
      // everything at or beyond `maxX` must be clipped away.
      let row = Array(try #require(halfway.rasterSurface.lines.first))
      let inside = String(row[min(rect.origin.x, row.count)..<min(rect.maxX, row.count)])
      #expect(inside.contains("ABCD"), "row: '\(String(row))'")
      #expect(
        !String(row).contains("ABCDE"), "content past the rect must be clipped: '\(String(row))'")
      #expect(
        row.indices.filter { $0 >= rect.maxX }.allSatisfy { row[$0] == " " },
        "nothing paints beyond the interpolated rect: '\(String(row))'"
      )

      let cells = halfway.rasterSurface.cells[0]
      let redColumns = cells.indices.filter { cells[$0].style?.backgroundColor == Color.red }
      #expect(
        redColumns == Array(rect.origin.x..<rect.maxX),
        "the background fill follows the interpolated rect: \(redColumns)"
      )
    }
  }
}

// MARK: - Fixtures

@MainActor
private struct MatchedRasterFixture: View {
  let wide: Bool

  var body: some View {
    HStack(spacing: 0) {
      if wide {
        Text("").frame(width: 10)
        hero(width: 8, label: "ABCDEFGH")
      } else {
        hero(width: 2, label: "AB")
        Text("").frame(width: 10)
      }
    }
  }

  private func hero(width: Int, label: String) -> some View {
    Button(label) {}
      .buttonStyle(.plain)
      .frame(width: width, alignment: .leading)
      .background(Color.red)
      .matchedGeometryEffect(id: "hero")
      .id("MatchedButton")
  }
}
