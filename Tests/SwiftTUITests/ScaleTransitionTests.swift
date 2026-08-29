import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph
@_spi(Runners) @testable import SwiftTUIRuntime
@testable import SwiftTUIViews

@MainActor
@Suite("Scale transition")
struct ScaleTransitionTests {
  private static let rootIdentity = testIdentity("ScaleTransition", "Root")
  private static let leafIdentity = testIdentity("ScaleTransition", "Leaf")
  private static let siblingIdentity = testIdentity("ScaleTransition", "Sibling")
  private static let leafNodeID = ViewNodeID(rawValue: 9_001)
  private static let leafBounds = CellRect(
    origin: CellPoint(x: 10, y: 2),
    size: CellSize(width: 8, height: 4)
  )

  @Test("built-ins match SwiftUI's default and parameterized phase modifiers")
  func builtinContracts() throws {
    let defaultInsertion = try #require(AnyTransition.scale.insertionModifiers().scale)
    let defaultRemoval = try #require(AnyTransition.scale.removalModifiers().scale)
    #expect(defaultInsertion.scale == 1e-5)
    #expect(defaultInsertion.anchor == .center)
    #expect(defaultRemoval == defaultInsertion)

    let custom = AnyTransition.scale(scale: 0.25, anchor: .bottomTrailing)
    let customInsertion = try #require(custom.insertionModifiers().scale)
    let customRemoval = try #require(custom.removalModifiers().scale)
    #expect(customInsertion.scale == 0.25)
    #expect(customInsertion.anchor == .bottomTrailing)
    #expect(customRemoval == customInsertion)

    let combined = AnyTransition.opacity.combined(with: custom).insertionModifiers()
    #expect(combined.opacity == 0)
    #expect(combined.scale == customInsertion)
  }

  @Test("scale preserves the selected anchor while cell bounds grow and shrink")
  func scaledBoundsPreserveAnchor() {
    #expect(
      scaledTransitionRect(Self.leafBounds, scale: 0.5, anchor: .topLeading)
        == CellRect(
          origin: CellPoint(x: 10, y: 2),
          size: CellSize(width: 4, height: 2)
        )
    )
    #expect(
      scaledTransitionRect(Self.leafBounds, scale: 0.5, anchor: .center)
        == CellRect(
          origin: CellPoint(x: 12, y: 3),
          size: CellSize(width: 4, height: 2)
        )
    )
    #expect(
      scaledTransitionRect(Self.leafBounds, scale: 0.5, anchor: .bottomTrailing)
        == CellRect(
          origin: CellPoint(x: 14, y: 4),
          size: CellSize(width: 4, height: 2)
        )
    )
    #expect(
      scaledTransitionRect(Self.leafBounds, scale: 1.5, anchor: .center)
        == CellRect(
          origin: CellPoint(x: 8, y: 1),
          size: CellSize(width: 12, height: 6)
        )
    )
  }

  @Test("insertion scales from the active factor to identity without moving siblings")
  func insertionScalesWithoutAffectingLayout() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let start = MonotonicInstant(offset: .seconds(500))

    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      ResolvedNode(identity: Self.rootIdentity, kind: .view("Root")),
      transaction: .init(),
      timestamp: start
    )

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: Self.leafIdentity,
      viewNodeID: Self.leafNodeID,
      transition: AnyTransition.scale(scale: 0.5, anchor: .bottomTrailing)
    )
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      ResolvedNode(
        identity: Self.rootIdentity,
        kind: .view("Root"),
        children: [
          ResolvedNode(
            viewNodeID: Self.leafNodeID,
            identity: Self.leafIdentity,
            kind: .view("Leaf")
          )
        ]
      ),
      transaction: transaction,
      timestamp: start
    )

    let placed = Self.placedTree(includingLeaf: true)
    let startSnapshot = controller.placedAnimationOverlaySnapshot(for: placed, at: start)
    let startScale = try #require(startSnapshot.insertionScales.first)
    #expect(startScale.scale == 0.5)
    #expect(startScale.anchor == .bottomTrailing)
    #expect(controller.activeInsertionScaleCount == 1)

    var startTree = placed
    applyPlacedAnimationOverlaySnapshot(startSnapshot, to: &startTree)
    let startLeaf = try #require(Self.node(Self.leafIdentity, in: startTree))
    #expect(
      startLeaf.bounds
        == CellRect(
          origin: CellPoint(x: 14, y: 4),
          size: CellSize(width: 4, height: 2)
        )
    )
    #expect(startLeaf.drawMetadata.clipsToBounds)
    #expect(startLeaf.clipBounds == startLeaf.bounds)
    let startFill = try #require(startLeaf.children.first)
    #expect(startFill.bounds == startLeaf.bounds)
    let sibling = try #require(Self.node(Self.siblingIdentity, in: startTree))
    #expect(sibling.bounds == CellRect(origin: .zero, size: CellSize(width: 3, height: 1)))

    let halfway = controller.placedAnimationOverlaySnapshot(
      for: placed,
      at: start.advanced(by: .milliseconds(500))
    )
    #expect(abs((try #require(halfway.insertionScales.first)).scale - 0.75) < 0.001)
    var halfwayTree = placed
    applyPlacedAnimationOverlaySnapshot(halfway, to: &halfwayTree)
    #expect(
      try #require(Self.node(Self.leafIdentity, in: halfwayTree)).bounds
        == CellRect(
          origin: CellPoint(x: 12, y: 3),
          size: CellSize(width: 6, height: 3)
        )
    )

    let completed = controller.placedAnimationOverlaySnapshot(
      for: placed,
      at: start.advanced(by: .milliseconds(1_500))
    )
    #expect(completed.insertionScales.isEmpty)
    #expect(controller.activeInsertionScaleCount == 0)
  }

  @Test("removal shrinks the frozen transient overlay toward its anchor")
  func removalScalesTransientOverlay() throws {
    let controller = AnimationController()
    let animation = Animation.linear(duration: .seconds(1))
    controller.register(animation)
    let start = MonotonicInstant(offset: .seconds(600))

    controller.beginTransitionCollection()
    controller.registerTransition(
      for: Self.leafIdentity,
      viewNodeID: Self.leafNodeID,
      transition: AnyTransition.scale(scale: 0.5, anchor: .bottomTrailing)
    )
    controller.finishTransitionCollection()
    controller.processResolvedTree(
      ResolvedNode(
        identity: Self.rootIdentity,
        kind: .view("Root"),
        children: [
          ResolvedNode(
            viewNodeID: Self.leafNodeID,
            identity: Self.leafIdentity,
            kind: .view("Leaf")
          )
        ]
      ),
      transaction: .init(),
      timestamp: start
    )
    controller.capturePlacedTree(Self.placedTree(includingLeaf: true))

    controller.beginTransitionCollection()
    controller.finishTransitionCollection()
    var transaction = TransactionSnapshot()
    transaction.animationRequest = .animate(animation.animationBox)
    controller.processResolvedTree(
      ResolvedNode(
        identity: Self.rootIdentity,
        kind: .view("Root"),
        children: [Self.siblingPlacedAsResolved]
      ),
      transaction: transaction,
      timestamp: start
    )

    let live = Self.placedTree(includingLeaf: false)
    let snapshot = controller.placedAnimationOverlaySnapshot(
      for: live,
      at: start.advanced(by: .milliseconds(500))
    )
    let removal = try #require(snapshot.removalOverlays.first)
    let scale = try #require(removal.modifiers.scale)
    #expect(abs(scale.scale - 0.75) < 0.001)
    #expect(scale.anchor == .bottomTrailing)

    var tree = live
    applyPlacedAnimationOverlaySnapshot(snapshot, to: &tree)
    let overlay = try #require(Self.node(Self.leafIdentity, in: tree))
    #expect(overlay.isTransient)
    #expect(
      overlay.bounds
        == CellRect(
          origin: CellPoint(x: 12, y: 3),
          size: CellSize(width: 6, height: 3)
        )
    )
    #expect(overlay.drawMetadata.clipsToBounds)
    let sibling = try #require(Self.node(Self.siblingIdentity, in: tree))
    #expect(sibling.bounds == CellRect(origin: .zero, size: CellSize(width: 3, height: 1)))
  }

  @Test("scale composes after matched geometry size and position")
  func scaleComposesAfterMatchedGeometry() throws {
    let destination = PlacedNode(
      identity: Self.leafIdentity,
      bounds: CellRect(
        origin: CellPoint(x: 40, y: 2),
        size: CellSize(width: 16, height: 8)
      )
    )
    var tree = PlacedNode(
      identity: Self.rootIdentity,
      bounds: CellRect(origin: .zero, size: CellSize(width: 80, height: 20)),
      children: [destination]
    )
    applyPlacedAnimationOverlaySnapshot(
      PlacedAnimationOverlaySnapshot(
        insertionScales: [
          .init(identity: Self.leafIdentity, scale: 0.5, anchor: .center)
        ],
        matchedGeometryOffsets: [
          .init(
            identity: Self.leafIdentity,
            dx: -20,
            dy: 0,
            size: CellSize(width: 8, height: 4)
          )
        ]
      ),
      to: &tree
    )
    let leaf = try #require(Self.node(Self.leafIdentity, in: tree))
    #expect(
      leaf.bounds
        == CellRect(
          origin: CellPoint(x: 22, y: 3),
          size: CellSize(width: 4, height: 2)
        )
    )
  }

  private static var siblingPlacedAsResolved: ResolvedNode {
    ResolvedNode(identity: siblingIdentity, kind: .view("Sibling"))
  }

  private static func placedTree(includingLeaf: Bool) -> PlacedNode {
    var children = [
      PlacedNode(
        identity: siblingIdentity,
        bounds: CellRect(origin: .zero, size: CellSize(width: 3, height: 1))
      )
    ]
    if includingLeaf {
      children.append(
        PlacedNode(
          identity: leafIdentity,
          bounds: leafBounds,
          children: [
            PlacedNode(
              identity: testIdentity("ScaleTransition", "Fill"),
              bounds: leafBounds
            )
          ]
        )
      )
    }
    return PlacedNode(
      identity: rootIdentity,
      bounds: CellRect(origin: .zero, size: CellSize(width: 40, height: 10)),
      children: children
    )
  }

  private static func node(_ identity: Identity, in tree: PlacedNode) -> PlacedNode? {
    if tree.identity == identity { return tree }
    for child in tree.children {
      if let found = node(identity, in: child) {
        return found
      }
    }
    return nil
  }
}
