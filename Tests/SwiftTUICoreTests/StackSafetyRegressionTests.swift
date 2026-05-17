import Testing

@_spi(Testing) @testable import SwiftTUICore

@Suite
struct StackSafetyRegressionTests {
  @Test("draw metadata preserves value semantics after copies mutate")
  func drawMetadataPreservesValueSemantics() {
    let original = DrawMetadata(
      foregroundStyle: .semantic(.foreground),
      listRowForegroundStyle: .semantic(.success),
      clipsToBounds: true
    )
    var copy = original

    copy.foregroundStyle = .semantic(.tint)
    copy.listRowForegroundStyle = .semantic(.warning)
    copy.clipsToBounds = false

    #expect(original.foregroundStyle == .semantic(.foreground))
    #expect(original.listRowForegroundStyle == .semantic(.success))
    #expect(original.clipsToBounds)

    #expect(copy.foregroundStyle == .semantic(.tint))
    #expect(copy.listRowForegroundStyle == .semantic(.warning))
    #expect(!copy.clipsToBounds)
  }

  @Test("placed node resolved metadata preserves value semantics after copies mutate")
  func placedNodeResolvedMetadataPreservesValueSemantics() {
    var original = PlacedNode(
      identity: testIdentity("placed-metadata"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      semanticMetadata: .init(accessibilityLabel: "original"),
      layoutBehavior: .padding(.init(top: 1, leading: 1, bottom: 1, trailing: 1))
    )
    original.drawMetadata.foregroundStyle = .semantic(.foreground)

    var copy = original
    var resolvedMetadata = copy.resolvedMetadata
    resolvedMetadata.semanticMetadata.accessibilityLabel = "copy"
    resolvedMetadata.drawMetadata.foregroundStyle = .semantic(.tint)
    resolvedMetadata.layoutBehavior = .offset(x: 1, y: 0)
    copy.resolvedMetadata = resolvedMetadata

    #expect(original.semanticMetadata.accessibilityLabel == "original")
    #expect(original.drawMetadata.foregroundStyle == .semantic(.foreground))
    #expect(
      original.layoutBehavior == .padding(.init(top: 1, leading: 1, bottom: 1, trailing: 1))
    )

    #expect(copy.semanticMetadata.accessibilityLabel == "copy")
    #expect(copy.drawMetadata.foregroundStyle == .semantic(.tint))
    #expect(copy.layoutBehavior == .offset(x: 1, y: 0))
  }

  @Test("resolved node descendant search remains stack-safe on deep trees")
  func resolvedNodeDescendantSearchRemainStackSafe() {
    let depth = 1024
    let tree = makeDeepResolvedNodeTree(depth: depth)

    #expect(tree.root.descendant(with: tree.leafIdentity)?.identity == tree.leafIdentity)
  }

  @Test("resolved node path lookup remains stack-safe on deep trees")
  func resolvedNodePathLookupRemainStackSafe() {
    let depth = 1024
    let tree = makeDeepResolvedNodeTree(depth: depth)

    #expect(tree.root.path(to: tree.leafIdentity) == expectedResolvedPath(depth: depth))
  }

  @Test("resolved node collection traversals remain stack-safe on deep trees")
  func resolvedNodeCollectionTraversalsRemainStackSafe() {
    let depth = 1024
    let tree = makeDeepResolvedNodeTree(depth: depth)

    let identities = tree.root.collectIdentities()
    #expect(identities.count == depth + 1)
    #expect(identities.first == tree.rootIdentity)
    #expect(identities.last == tree.leafIdentity)

    var appearIDs: [String] = []
    var disappearIDs: [String] = []
    tree.root.collectLifecycleHandlerIDs(
      appearIDs: &appearIDs,
      disappearIDs: &disappearIDs
    )
    #expect(
      appearIDs
        == [
          "resolved-root-appear",
          "resolved-middle-appear",
          "resolved-leaf-appear",
        ]
    )
    #expect(
      disappearIDs
        == [
          "resolved-root-disappear",
          "resolved-middle-disappear",
          "resolved-leaf-disappear",
        ]
    )

    var lifecycleNodes: [LifecycleStateNode] = []
    tree.root.collectLifecycleNodes(into: &lifecycleNodes)
    #expect(
      lifecycleNodes.map(\.identity)
        == [tree.rootIdentity, tree.middleIdentity, tree.leafIdentity]
    )
  }

  @Test("placed node traversals remain stack-safe on deep trees")
  func placedNodeTraversalsRemainStackSafe() {
    let tree = makeDeepPlacedNodeTree(depth: 1024)

    let snapshot = SemanticExtractor().extract(from: tree.root)
    #expect(snapshot.focusRegions.count == 1)
    #expect(snapshot.focusRegions.first?.identity == tree.leafIdentity)
    #expect(snapshot.interactionRegions.count == 1)
    #expect(snapshot.interactionRegions.first?.identity == tree.leafIdentity)

    let draw = DrawExtractor().extract(from: tree.root)
    let surface = Rasterizer().rasterize(draw)
    #expect(surface.size == .init(width: 1, height: 1))
    #expect(surface.cells[0][0].character == "A")

    var lifecycleNodes: [LifecycleStateNode] = []
    tree.root.collectLifecycleNodes(into: &lifecycleNodes)
    #expect(
      lifecycleNodes.map(\.identity)
        == [tree.rootIdentity, tree.middleIdentity, tree.leafIdentity]
    )
  }

  @Test("deep draw trees rasterize without recursive command walking")
  func deepDrawTreesRasterizeWithoutRecursiveCommandWalking() {
    let rasterizer = Rasterizer()
    let draw = makeDeepDrawTree(depth: 256)

    let surface = rasterizer.rasterize(draw)
    #expect(surface.size == .init(width: 1, height: 1))
    #expect(surface.cells[0][0].character == "A")
  }

  @Test("post-layout render node metadata stays within stack-safety budgets")
  func renderNodeLayoutsStayWithinBudget() {
    #expect(MemoryLayout<DrawMetadata>.size <= 128)
    #expect(MemoryLayout<PlacedNode>.size <= 768)
    #expect(MemoryLayout<DrawNode>.size <= 256)
  }
}

private struct DeepResolvedTree {
  let root: ResolvedNode
  let rootIdentity: Identity
  let middleIdentity: Identity
  let leafIdentity: Identity
}

private struct DeepPlacedTree {
  let root: PlacedNode
  let rootIdentity: Identity
  let middleIdentity: Identity
  let leafIdentity: Identity
}

private func makeDeepResolvedNodeTree(depth: Int) -> DeepResolvedTree {
  let rootIdentity = testIdentity("resolved", "0")
  let middleIdentity = testIdentity("resolved", "\(depth / 2)")
  let leafIdentity = testIdentity("resolved", "leaf")

  var leafSemanticMetadata = SemanticMetadata(isFocusable: true)
  leafSemanticMetadata.focusScopeBoundary = true
  let leafLifecycleMetadata = LifecycleMetadata(
    appearHandlerIDs: ["resolved-leaf-appear"],
    disappearHandlerIDs: ["resolved-leaf-disappear"]
  )
  var node = ResolvedNode(
    identity: leafIdentity,
    kind: .view("Button"),
    semanticMetadata: leafSemanticMetadata,
    lifecycleMetadata: leafLifecycleMetadata
  )

  for index in stride(from: depth - 1, through: 0, by: -1) {
    let identity = testIdentity("resolved", "\(index)")
    let lifecycleMetadata: LifecycleMetadata
    if index == 0 {
      lifecycleMetadata = .init(
        appearHandlerIDs: ["resolved-root-appear"],
        disappearHandlerIDs: ["resolved-root-disappear"]
      )
    } else if index == depth / 2 {
      lifecycleMetadata = .init(
        appearHandlerIDs: ["resolved-middle-appear"],
        disappearHandlerIDs: ["resolved-middle-disappear"]
      )
    } else {
      lifecycleMetadata = .init()
    }

    node = ResolvedNode(
      identity: identity,
      kind: .view("Container"),
      children: [node],
      lifecycleMetadata: lifecycleMetadata
    )
  }

  return DeepResolvedTree(
    root: node,
    rootIdentity: rootIdentity,
    middleIdentity: middleIdentity,
    leafIdentity: leafIdentity
  )
}

private func expectedResolvedPath(depth: Int) -> [Identity] {
  var path: [Identity] = [testIdentity("resolved", "0")]
  for index in 1..<depth {
    path.append(testIdentity("resolved", "\(index)"))
  }
  path.append(testIdentity("resolved", "leaf"))
  return path
}

private func makeDeepPlacedNodeTree(depth: Int) -> DeepPlacedTree {
  let rootIdentity = testIdentity("placed", "0")
  let middleIdentity = testIdentity("placed", "\(depth / 2)")
  let leafIdentity = testIdentity("placed", "leaf")

  var leafSemanticMetadata = SemanticMetadata(isFocusable: true)
  leafSemanticMetadata.focusScopeBoundary = true
  let leafLifecycleMetadata = LifecycleMetadata(
    appearHandlerIDs: ["placed-leaf-appear"],
    disappearHandlerIDs: ["placed-leaf-disappear"]
  )
  var node = PlacedNode(
    identity: leafIdentity,
    kind: .view("Button"),
    bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
    semanticMetadata: leafSemanticMetadata,
    lifecycleMetadata: leafLifecycleMetadata,
    drawPayload: .text("A")
  )

  for index in stride(from: depth - 1, through: 0, by: -1) {
    let identity = testIdentity("placed", "\(index)")
    let lifecycleMetadata: LifecycleMetadata
    if index == 0 {
      lifecycleMetadata = .init(
        appearHandlerIDs: ["placed-root-appear"],
        disappearHandlerIDs: ["placed-root-disappear"]
      )
    } else if index == depth / 2 {
      lifecycleMetadata = .init(
        appearHandlerIDs: ["placed-middle-appear"],
        disappearHandlerIDs: ["placed-middle-disappear"]
      )
    } else {
      lifecycleMetadata = .init()
    }

    node = PlacedNode(
      identity: identity,
      kind: .view("Container"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      children: [node],
      lifecycleMetadata: lifecycleMetadata
    )
  }

  return DeepPlacedTree(
    root: node,
    rootIdentity: rootIdentity,
    middleIdentity: middleIdentity,
    leafIdentity: leafIdentity
  )
}

private func makeDeepDrawTree(depth: Int) -> DrawNode {
  let leafIdentity = testIdentity("draw", "leaf")
  let textBounds = CellRect(origin: .zero, size: .init(width: 1, height: 1))
  var command: DrawCommand = .text(
    bounds: textBounds,
    content: "A",
    style: .init(),
    lineLimit: nil,
    truncationMode: .tail,
    wrappingStrategy: .wordBoundary
  )

  for index in 0..<depth {
    if index.isMultiple(of: 2) {
      command = .group(bounds: textBounds, children: [command])
    } else {
      command = .clip(bounds: textBounds, child: command)
    }
  }

  var node = DrawNode(
    identity: leafIdentity,
    bounds: textBounds,
    commands: [command]
  )

  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = DrawNode(
      identity: testIdentity("draw", "\(index)"),
      bounds: textBounds,
      children: [node]
    )
  }

  return node
}
