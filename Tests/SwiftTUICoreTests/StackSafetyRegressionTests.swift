import Testing

@_spi(Testing) @testable import SwiftTUICore
@testable import SwiftTUIGraph

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

  @Test("deep wrapper chains measure and place through layout engine")
  func deepWrapperChainsMeasureAndPlaceThroughLayoutEngine() {
    let engine = LayoutEngine()
    let resolved = makeDeepLayoutWrapperChain(depth: 8)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 12, height: 4)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.measuredSize.width > 0)
    #expect(measured.measuredSize.height > 0)
    #expect(placed.subtreeNodeCount == measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep wrapper chains place through explicit layout work stack")
  func deepWrapperChainsPlaceThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepLayoutWrapperChain(depth: 1024)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 12, height: 4)
    )
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: passContext
    )

    #expect(passContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.subtreeNodeCount == measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep wrapper chains measure through explicit layout work stack")
  func deepWrapperChainsMeasureThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepLayoutWrapperChain(depth: 1024)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 12, height: 4),
      passContext: passContext
    )

    #expect(passContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(measured.subtreeNodeCount == resolved.subtreeNodeCount)
    #expect(measured.measuredSize.width > 0)
    #expect(measured.measuredSize.height > 0)
  }

  @Test("deep stack chains measure and place through layout engine")
  func deepStackChainsMeasureAndPlaceThroughLayoutEngine() {
    let engine = LayoutEngine()
    let resolved = makeDeepStackLayoutChain(depth: 6)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 16, height: 16)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.subtreeNodeCount == resolved.subtreeNodeCount)
    #expect(placed.subtreeNodeCount > 0)
    #expect(placed.subtreeNodeCount <= measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep stack chains place through explicit layout work stack")
  func deepStackChainsPlaceThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepStackLayoutChain(depth: 128)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 128, height: 128)
    )
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: passContext
    )

    #expect(passContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.subtreeNodeCount > 0)
    #expect(placed.subtreeNodeCount <= measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep stack chains measure through explicit layout work stack")
  func deepStackChainsMeasureThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepStackLayoutChain(depth: 64)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 64, height: 64),
      passContext: passContext
    )

    #expect(passContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(measured.subtreeNodeCount == resolved.subtreeNodeCount)
    #expect(measured.measuredSize.width > 0)
    #expect(measured.measuredSize.height > 0)
  }

  @Test("deep branching built-in trees measure and place through layout engine")
  func deepBranchingBuiltInTreesMeasureAndPlaceThroughLayoutEngine() {
    let engine = LayoutEngine()
    let resolved = makeDeepBranchingLayoutTree(depth: 6)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 8)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.subtreeNodeCount == resolved.subtreeNodeCount)
    #expect(placed.subtreeNodeCount > 0)
    #expect(placed.subtreeNodeCount <= measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep branching built-in trees place through explicit layout work stack")
  func deepBranchingBuiltInTreesPlaceThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepBranchingLayoutTree(depth: 64)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 8)
    )
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: passContext
    )

    #expect(passContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.subtreeNodeCount > 0)
    #expect(placed.subtreeNodeCount <= measured.subtreeNodeCount)
    #expect(placed.bounds.size == measured.measuredSize)
  }

  @Test("deep branching built-in trees measure through explicit layout work stack")
  func deepBranchingBuiltInTreesMeasureThroughExplicitLayoutWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let resolved = makeDeepBranchingLayoutTree(depth: 64)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 20, height: 8),
      passContext: passContext
    )

    #expect(passContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(measured.subtreeNodeCount == resolved.subtreeNodeCount)
    #expect(measured.measuredSize.width > 0)
    #expect(measured.measuredSize.height > 0)
  }

  @MainActor
  @Test("layout-realized placement measures realized children through layout engine")
  func layoutRealizedPlacementMeasuresRealizedChildrenThroughLayoutEngine() {
    let engine = LayoutEngine()
    let child = makeLayoutLeaf("layout-realized-child", size: .init(width: 3, height: 1))
    let resolved = makeLayoutRealizedNode(children: [child])

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 10, height: 3)
    )
    let placeContext = LayoutPassContext()
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: placeContext
    )

    #expect(measured.measuredSize == .init(width: 10, height: 3))
    #expect(placeContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(placeContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.children.count == 1)
    #expect(placed.children.first?.identity == child.identity)
    #expect(placed.children.first?.bounds.size == child.intrinsicSize)
  }

  @Test("indexed lazy stack placement measures visible children through layout engine")
  func indexedLazyStackPlacementMeasuresVisibleChildrenThroughLayoutEngine() {
    let engine = LayoutEngine()
    let children = (0..<8).map {
      makeLayoutLeaf("indexed-lazy-child-\($0)", size: .init(width: 2, height: 1))
    }
    let resolved = makeIndexedLazyStackLayoutTree(
      "indexed-lazy-root",
      axis: .vertical,
      children: children
    )

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 8, height: 4)
    )
    let placeContext = LayoutPassContext()
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: placeContext
    )

    #expect(measured.containerAllocationSnapshot?.lazyStack != nil)
    #expect(placeContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(placeContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.children.count == children.count)
    #expect(placed.children.map(\.identity) == children.map(\.identity))
  }

  @Test("custom layout compatibility depth limit records runtime issues")
  func customLayoutCompatibilityDepthLimitRecordsRuntimeIssues() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext(customLayoutCompatibilityDepthLimit: 2)
    let resolved = makeRecursiveCustomLayoutChain(depth: 80)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 8, height: 4),
      passContext: passContext
    )
    _ = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: passContext
    )

    #expect(
      passContext.runtimeIssues.contains {
        $0.code == "layout.customLayoutDepthLimitExceeded"
          && $0.message.contains("measurement")
      }
    )
    #expect(
      passContext.runtimeIssues.contains {
        $0.code == "layout.customLayoutDepthLimitExceeded"
          && $0.message.contains("placement")
      }
    )
  }

  @Test("direct core custom layout calls apply deterministic compatibility limit")
  func directCoreCustomLayoutCallsApplyDeterministicCompatibilityLimit() {
    let engine = LayoutEngine()
    let resolved = makeRecursiveCustomLayoutChain(depth: 20)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 8, height: 4)
    )
    let placed = engine.place(resolved, measured: measured, origin: .zero)

    #expect(measured.identity == resolved.identity)
    #expect(placed.identity == resolved.identity)
  }

  @Test("worker-safe custom layout children measure through explicit work stack")
  func workerSafeCustomLayoutChildrenMeasureThroughExplicitWorkStack() {
    let engine = LayoutEngine()
    let passContext = LayoutPassContext()
    let children = [
      makeLayoutLeaf("worker-custom-child-0", size: .init(width: 2, height: 1)),
      makeLayoutLeaf("worker-custom-child-1", size: .init(width: 3, height: 1)),
    ]
    let resolved = makeWorkerSafeCustomLayoutNode(children: children)

    let measured = engine.measure(
      resolved,
      proposal: .init(width: 8, height: 4),
      passContext: passContext
    )
    let placed = engine.place(
      resolved,
      measured: measured,
      origin: .zero,
      passContext: passContext
    )

    #expect(passContext.workMetrics.measurementWorkStackSteps > 0)
    #expect(passContext.workMetrics.placementWorkStackSteps > 0)
    #expect(placed.children.map(\.identity) == children.map(\.identity))
  }

  @Test("post-layout render node metadata stays within stack-safety budgets")
  func renderNodeLayoutsStayWithinBudget() {
    #expect(MemoryLayout<DrawEffects>.size <= 16)
    #expect(MemoryLayout<DrawMetadata>.size <= 128)
    #expect(MemoryLayout<PlacedNode>.size <= 768)
    #expect(MemoryLayout<DrawNode>.size <= 256)
  }
}

private let recursiveCustomLayoutProxy = RecursiveCustomLayoutProxy()

private func makeRecursiveCustomLayoutChain(depth: Int) -> ResolvedNode {
  var node = makeLayoutLeaf("recursive-custom-leaf", size: .init(width: 1, height: 1))

  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = ResolvedNode(
      identity: testIdentity("recursive-custom", "\(index)"),
      kind: .view("RecursiveCustomLayout"),
      children: [node],
      layoutBehavior: .custom(CustomLayoutHandle(recursiveCustomLayoutProxy))
    )
  }

  return node
}

private final class RecursiveCustomLayoutProxy: LayoutPassContextCustomLayoutProxy {
  var debugName: String {
    "RecursiveCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize
  ) -> CellSize {
    .init(width: 1, height: 1)
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize,
    passContext _: LayoutPassContext?
  ) -> CellSize {
    .init(width: 1, height: 1)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect
  ) -> [PlacedNode] {
    placeSubviews(
      engine: engine,
      node: node,
      measured: measured,
      in: bounds,
      passContext: nil
    )
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    node.children.map { child in
      let childMeasurement = engine.measure(
        child,
        proposal: measured.proposal,
        passContext: passContext
      )
      return engine.place(
        child,
        measured: childMeasurement,
        in: CellRect(origin: bounds.origin, size: childMeasurement.measuredSize),
        passContext: passContext
      )
    }
  }
}

private func makeWorkerSafeCustomLayoutNode(children: [ResolvedNode]) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity("worker-custom-root"),
    kind: .view("WorkerSafeCustomLayout"),
    children: children,
    layoutBehavior: .custom(
      CustomLayoutHandle(
        RecursiveCustomLayoutProxy(),
        workerProxy: StackSafetyWorkerCustomLayoutProxy()
      )
    )
  )
}

private struct StackSafetyWorkerCustomLayoutProxy: WorkerCustomLayoutProxy {
  var debugName: String {
    "StackSafetyWorkerCustomLayoutProxy"
  }

  func measureContainer(
    engine _: LayoutEngine,
    node _: ResolvedNode,
    proposal _: ProposedSize,
    passContext _: LayoutPassContext?
  ) -> CellSize {
    .init(width: 3, height: 2)
  }

  func placeSubviews(
    engine: LayoutEngine,
    node: ResolvedNode,
    measured: MeasuredNode,
    in bounds: CellRect,
    passContext: LayoutPassContext?
  ) -> [PlacedNode] {
    var y = bounds.origin.y
    return node.children.map { child in
      let childMeasurement = engine.measure(
        child,
        proposal: measured.proposal,
        passContext: passContext
      )
      defer {
        y += childMeasurement.measuredSize.height
      }
      return engine.place(
        child,
        measured: childMeasurement,
        in: CellRect(
          origin: .init(x: bounds.origin.x, y: y),
          size: childMeasurement.measuredSize
        ),
        passContext: passContext
      )
    }
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

private func makeLayoutLeaf(
  _ name: String,
  size: CellSize
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view("Leaf"),
    intrinsicSize: size
  )
}

private func makeDeepLayoutWrapperChain(depth: Int) -> ResolvedNode {
  var node = makeLayoutLeaf("wrapper-leaf", size: .init(width: 1, height: 1))

  for index in stride(from: depth - 1, through: 0, by: -1) {
    node = ResolvedNode(
      identity: testIdentity("wrapper", "\(index)"),
      kind: .view("Wrapper"),
      children: [node],
      layoutBehavior: wrapperBehavior(for: index)
    )
  }

  return node
}

private func wrapperBehavior(for index: Int) -> LayoutBehavior {
  switch index % 7 {
  case 0:
    return .padding(.init(top: 0, leading: 1, bottom: 0, trailing: 1))
  case 1:
    return .safeAreaIgnoring(.init())
  case 2:
    return .border(
      .single,
      placement: .inset,
      foreground: nil,
      background: nil,
      blend: nil,
      blendPhase: 0,
      sides: .all
    )
  case 3:
    return .frame(width: nil, height: nil, alignment: .center)
  case 4:
    return .flexibleFrame(
      minWidth: nil,
      idealWidth: nil,
      maxWidth: .infinity,
      minHeight: nil,
      idealHeight: nil,
      maxHeight: .infinity,
      alignment: .center
    )
  case 5:
    return .offset(x: 1, y: 0)
  default:
    return .position(x: 0, y: 0)
  }
}

private func makeDeepStackLayoutChain(depth: Int) -> ResolvedNode {
  var node = makeLayoutLeaf("stack-leaf", size: .init(width: 1, height: 1))

  for index in stride(from: depth - 1, through: 0, by: -1) {
    let sibling = makeLayoutLeaf("stack-sibling-\(index)", size: .init(width: 1, height: 1))
    node = ResolvedNode(
      identity: testIdentity("stack", "\(index)"),
      kind: .view(index.isMultiple(of: 2) ? "VStack" : "HStack"),
      children: [node, sibling],
      layoutBehavior: .stack(
        axis: index.isMultiple(of: 2) ? .vertical : .horizontal,
        spacing: 0,
        horizontalAlignment: .leading,
        verticalAlignment: .top
      )
    )
  }

  return node
}

private func makeDeepBranchingLayoutTree(depth: Int) -> ResolvedNode {
  var node = makeLayoutLeaf("branch-leaf", size: .init(width: 2, height: 1))

  for index in stride(from: depth - 1, through: 0, by: -1) {
    let adornment = makeLayoutLeaf("branch-adornment-\(index)", size: .init(width: 1, height: 1))
    switch index % 4 {
    case 0:
      node = ResolvedNode(
        identity: testIdentity("branch-overlay", "\(index)"),
        kind: .view("Overlay"),
        children: [node, adornment],
        layoutBehavior: .overlay(alignment: .center)
      )
    case 1:
      node = ResolvedNode(
        identity: testIdentity("branch-decoration", "\(index)"),
        kind: .view("Decoration"),
        children: [adornment, node],
        layoutBehavior: .decoration(primaryIndex: 1, alignment: .center)
      )
    case 2:
      node = ResolvedNode(
        identity: testIdentity("branch-inset", "\(index)"),
        kind: .view("SafeAreaInset"),
        children: [node, adornment],
        layoutBehavior: .safeAreaInset(
          edge: .top,
          alignment: .center,
          spacing: 0,
          safeArea: .init()
        )
      )
    default:
      node = ResolvedNode(
        identity: testIdentity("branch-view-that-fits", "\(index)"),
        kind: .view("ViewThatFits"),
        children: [node, adornment],
        layoutBehavior: .viewThatFits([.horizontal, .vertical])
      )
    }
  }

  return node
}

@MainActor
private func makeLayoutRealizedNode(children: [ResolvedNode]) -> ResolvedNode {
  let identity = testIdentity("layout-realized-root")
  let realizer = TestLayoutDependentContentRealizer(children: children)
  let boundary = LayoutRealizedContentBoundary(
    identity: identity,
    sizingPolicy: .fillsProposal(unspecifiedIdeal: .init(width: 4, height: 2)),
    safeAreaInsets: .init(),
    cellPixelMetrics: .estimated,
    pointerInputCapabilities: .cellOnly,
    debugName: "TestLayoutDependentContent",
    handle: LayoutDependentContentHandle(realizer)
  )
  return ResolvedNode(
    identity: identity,
    kind: .view("LayoutRealized"),
    layoutRealizedContent: boundary
  )
}

@MainActor
private final class TestLayoutDependentContentRealizer: LayoutDependentContentRealizer {
  let children: [ResolvedNode]

  init(children: [ResolvedNode]) {
    self.children = children
  }

  var debugName: String {
    "TestLayoutDependentContent"
  }

  func realize(in _: LayoutRealizationContext) -> [ResolvedNode] {
    children
  }
}

private func makeIndexedLazyStackLayoutTree(
  _ name: String,
  axis: Axis,
  children: [ResolvedNode]
) -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity(name),
    kind: .view(axis == .horizontal ? "LazyHStack" : "LazyVStack"),
    layoutBehavior: .lazyStack(
      axis: axis,
      spacing: 0,
      horizontalAlignment: .leading,
      verticalAlignment: .top
    ),
    indexedChildSource: TestStackSafetyIndexedChildSource(
      identityRoot: testIdentity(name),
      children: children
    )
  )
}

private struct TestStackSafetyIndexedChildSource: IndexedChildSource {
  let identityRoot: Identity
  let measurementSignature: String
  private let children: [ResolvedNode]

  init(
    identityRoot: Identity,
    children: [ResolvedNode]
  ) {
    self.identityRoot = identityRoot
    self.children = children
    self.measurementSignature = children.map(\.identity.path).joined(separator: "|")
  }

  var count: Int {
    children.count
  }

  func child(at index: Int) -> ResolvedNode {
    children[index]
  }
}
