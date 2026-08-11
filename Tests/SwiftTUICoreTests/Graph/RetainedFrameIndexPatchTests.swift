import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

/// Pins the shape-stable incremental patch behind
/// `RetainedFrameIndex.init(patching:with:)`: value-only frames patch
/// (`derivedByPatching`), every structural or ambiguous frame falls back to a
/// full rebuild, and both arms stay byte-equivalent to a fresh rebuild. In
/// DEBUG the initializer additionally self-checks every patched frame against
/// a rebuild, so a divergence in any of these tests is a crash, not a silent
/// wrong answer.
@Suite
struct RetainedFrameIndexPatchTests {
  @Test("a value-only frame patches and serves the new placed bounds")
  func valueOnlyFramePatches() throws {
    let tree = twoRowTree()
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: tree))
    let movedBounds = CellRect(origin: .init(x: 3, y: 4), size: .init(width: 5, height: 1))
    let updatedFrame = frame(
      resolvedTree: tree,
      boundsByIdentity: [testIdentity("Root", "B"): movedBounds]
    )

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
    #expect(patched.placedNode(for: testIdentity("Root", "B"))?.bounds == movedBounds)
    #expect(patched.placedNode(for: testIdentity("Root", "A"))?.bounds == .zero)
  }

  @Test("a resolved payload change under a stable shape patches")
  func resolvedPayloadChangePatches() throws {
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: twoRowTree()))
    var updatedTree = twoRowTree()
    updatedTree.children[0].intrinsicSize = .init(width: 9, height: 2)
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
    #expect(
      patched.resolvedNode(for: testIdentity("Root", "A"))?.intrinsicSize
        == CellSize(width: 9, height: 2)
    )
  }

  @Test("the flat placed-entry table reflects a patched node's bounds")
  func placedFrameFragmentReflectsPatch() throws {
    let tree = twoRowTree()
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: tree))
    let movedBounds = CellRect(origin: .init(x: 1, y: 2), size: .init(width: 3, height: 1))
    let updatedFrame = frame(
      resolvedTree: tree,
      boundsByIdentity: [testIdentity("Root", "A"): movedBounds]
    )

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)
    let fragment = try #require(patched.placedFrameFragment(for: testIdentity("Root", "A")))

    #expect(patched.derivedByPatching)
    #expect(fragment.entries.contains { $0.identity == testIdentity("Root", "A") && $0.bounds == movedBounds })
  }

  @Test("an inserted sibling falls back to a full rebuild")
  func insertionFallsBack() {
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: twoRowTree()))
    var updatedTree = twoRowTree()
    updatedTree.children.append(
      ResolvedNode(identity: testIdentity("Root", "C"), kind: .view("Text"))
    )
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(!patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
  }

  @Test("a removed sibling falls back to a full rebuild")
  func deletionFallsBack() {
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: twoRowTree()))
    var updatedTree = twoRowTree()
    updatedTree.children.removeLast()
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(!patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
  }

  @Test("reordered sibling identities fall back to a full rebuild")
  func reorderFallsBack() {
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: twoRowTree()))
    var updatedTree = twoRowTree()
    updatedTree.children.reverse()
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(!patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
  }

  @Test("a node-kind change under a stable identity falls back to a full rebuild")
  func kindChangeFallsBack() {
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: twoRowTree()))
    var updatedTree = twoRowTree()
    updatedTree.children[0] = ResolvedNode(
      identity: testIdentity("Root", "A"),
      kind: .view("Renamed")
    )
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(!patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
  }

  @Test("duplicate runtime identities force the rebuild arm")
  func duplicateIdentitiesFallBack() {
    let duplicate = testIdentity("Root", "ID[dup]")
    let tree = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: duplicate, kind: .view("Row")),
        ResolvedNode(identity: duplicate, kind: .view("Row")),
      ]
    )
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: tree))

    let patched = RetainedFrameIndex(patching: previous, with: frame(resolvedTree: tree))

    #expect(!patched.derivedByPatching)
  }

  @Test("a ViewNodeID reassignment under a stable shape rekeys the node tables")
  func viewNodeIDReassignmentRekeys() throws {
    var initialTree = twoRowTree()
    initialTree.children[0].viewNodeID = ViewNodeID(rawValue: 1)
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: initialTree))

    var updatedTree = twoRowTree()
    updatedTree.children[0].viewNodeID = ViewNodeID(rawValue: 2)
    updatedTree.children[0].intrinsicSize = .init(width: 4, height: 1)
    let updatedFrame = frame(resolvedTree: updatedTree)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)

    #expect(patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: RetainedFrameIndex(frame: updatedFrame)))
    #expect(patched.resolvedByNodeID[ViewNodeID(rawValue: 1)] == nil)
    #expect(patched.resolvedByNodeID[ViewNodeID(rawValue: 2)] != nil)
  }

  @Test("nested nodes sharing a ViewNodeID keep the rebuild's collapse winners")
  func sharedViewNodeIDCollapseMatchesRebuild() throws {
    // Transparent chain absorption stamps absorbed levels with the absorber's
    // id, so nested placed nodes legitimately share one ViewNodeID — and the
    // rebuild collapses the storage table by last-preorder writer but the
    // range table by last-postorder writer. This is the production shape that
    // refuted the first surgical-rekey patch design.
    var inner = ResolvedNode(
      identity: testIdentity("Root", "wrap", "leaf"),
      kind: .view("Text")
    )
    inner.viewNodeID = ViewNodeID(rawValue: 7)
    var wrap = ResolvedNode(
      identity: testIdentity("Root", "wrap"),
      kind: .view("Frame"),
      children: [inner]
    )
    wrap.viewNodeID = ViewNodeID(rawValue: 7)
    let tree = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [wrap]
    )
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: tree))
    let movedBounds = CellRect(origin: .init(x: 2, y: 1), size: .init(width: 4, height: 2))
    let updatedFrame = frame(
      resolvedTree: tree,
      boundsByIdentity: [testIdentity("Root", "wrap"): movedBounds]
    )

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)
    let rebuilt = RetainedFrameIndex(frame: updatedFrame)

    #expect(patched.derivedByPatching)
    #expect(patched.byteDivergenceDescription(from: rebuilt) == nil)
  }

  @Test("an identical frame patches without rewriting any node table entry")
  func identicalFramePatches() {
    let tree = twoRowTree()
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: tree))

    let patched = RetainedFrameIndex(patching: previous, with: frame(resolvedTree: tree))

    #expect(patched.derivedByPatching)
    #expect(patched.isByteEquivalent(to: previous))
  }

  @Test("the first frame has no previous index and rebuilds")
  func firstFrameRebuilds() {
    let index = RetainedFrameIndex(patching: nil, with: frame(resolvedTree: twoRowTree()))

    #expect(!index.derivedByPatching)
  }
}

private func twoRowTree() -> ResolvedNode {
  ResolvedNode(
    identity: testIdentity("Root"),
    kind: .root,
    children: [
      ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Text")),
      ResolvedNode(identity: testIdentity("Root", "B"), kind: .view("Text")),
    ]
  )
}

private func frame(
  resolvedTree: ResolvedNode,
  boundsByIdentity: [Identity: CellRect] = [:]
) -> FrameArtifacts {
  FrameArtifacts(
    resolvedTree: resolvedTree,
    measuredTree: measuredTree(from: resolvedTree),
    placedTree: placedTree(from: resolvedTree, boundsByIdentity: boundsByIdentity),
    semanticSnapshot: .init(),
    drawTree: drawTree(from: resolvedTree),
    rasterSurface: .init(),
    presentationDamage: nil,
    drawnIdentities: [],
    commitPlan: .init()
  )
}

private func measuredTree(
  from node: ResolvedNode
) -> MeasuredNode {
  MeasuredNode(
    viewNodeID: node.viewNodeID,
    identity: node.identity,
    proposal: .unspecified,
    measuredSize: .zero,
    childMeasurements: node.children.map(measuredTree(from:))
  )
}

private func placedTree(
  from node: ResolvedNode,
  boundsByIdentity: [Identity: CellRect]
) -> PlacedNode {
  PlacedNode(
    viewNodeID: node.viewNodeID,
    identity: node.identity,
    kind: node.kind,
    bounds: boundsByIdentity[node.identity] ?? .init(origin: .zero, size: .zero),
    children: node.children.map { placedTree(from: $0, boundsByIdentity: boundsByIdentity) }
  )
}

private func drawTree(
  from node: ResolvedNode
) -> DrawNode {
  DrawNode(
    identity: node.identity,
    bounds: .init(origin: .zero, size: .zero),
    children: node.children.map(drawTree(from:))
  )
}
