import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct DrawExtractorTraversalTests {
  @Test("deeply nested placed trees extract without recursion limits")
  func deeplyNestedPlacedTreesExtract() {
    let depth = 2_000
    let root = makeDeepPlacedTree(depth: depth)

    let draw = DrawExtractor().extract(from: root)

    #expect(draw.subtreeNodeCount == depth + 1)

    var current = draw
    var visited = 1
    while let child = current.children.first {
      visited += 1
      current = child
    }

    #expect(visited == depth + 1)
    #expect(current.identity == testIdentity("leaf"))
  }

  @Test("draw extraction preserves sibling order")
  func drawExtractionPreservesSiblingOrder() {
    let root = PlacedNode(
      identity: testIdentity("root"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      children: [
        PlacedNode(
          identity: testIdentity("left"),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
          children: [
            PlacedNode(
              identity: testIdentity("left-leaf"),
              bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
          ]
        ),
        PlacedNode(
          identity: testIdentity("right"),
          bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
          children: [
            PlacedNode(
              identity: testIdentity("right-leaf"),
              bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
            )
          ]
        ),
      ]
    )

    let draw = DrawExtractor().extract(from: root)

    #expect(draw.children.map(\.identity) == [testIdentity("left"), testIdentity("right")])
    #expect(
      draw.children[0].children.map(\.identity) == [testIdentity("left-leaf")]
    )
    #expect(
      draw.children[1].children.map(\.identity) == [testIdentity("right-leaf")]
    )
  }
}

private func makeDeepPlacedTree(depth: Int) -> PlacedNode {
  var node = PlacedNode(
    identity: testIdentity("leaf"),
    bounds: .init(origin: .zero, size: .init(width: 1, height: 1))
  )

  if depth == 0 {
    return node
  }

  for index in (0..<depth).reversed() {
    node = PlacedNode(
      identity: testIdentity("node", "\(index)"),
      bounds: .init(origin: .zero, size: .init(width: 1, height: 1)),
      children: [node]
    )
  }

  return node
}
