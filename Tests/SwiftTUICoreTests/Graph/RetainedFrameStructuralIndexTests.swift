import Testing

@testable import SwiftTUICore
@testable import SwiftTUIGraph

@Suite
struct RetainedFrameStructuralIndexTests {
  @Test("structural index records the real children-array parent")
  func structuralIndexRecordsRealParent() throws {
    let child = ResolvedNode(
      identity: testIdentity("Root", "Slot[0]", "ID[42]"),
      kind: .view("Text")
    )
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [child]
    )

    let index = RetainedFrameIndex(frame: frame(resolvedTree: root))
    let childKey = try #require(index.structuralFrame.uniqueNode(for: child.identity))

    #expect(index.structuralFrame.parentIdentity(of: childKey) == testIdentity("Root"))
    #expect(child.identity.parent == testIdentity("Root", "Slot[0]"))
  }

  @Test("duplicate runtime identities are retained as structural multimap entries")
  func duplicateRuntimeIdentitiesAreMultimapped() {
    let duplicate = testIdentity("Root", "ForEach[0]", "ID[dup]")
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: duplicate, kind: .view("Row")),
        ResolvedNode(identity: duplicate, kind: .view("Row")),
      ]
    )

    let index = RetainedFrameIndex(frame: frame(resolvedTree: root))

    #expect(index.resolvedNode(for: duplicate) != nil)
    #expect(index.structuralFrame.nodes(for: duplicate).count == 2)
    // G12: the flat identity-keyed accessor collapses the collision
    // last-writer-wins, but the index makes it queryable rather than silent.
    #expect(index.duplicateRuntimeIdentities == [duplicate])
  }

  @Test("a collision-free frame reports no duplicate runtime identities")
  func uniqueRuntimeIdentitiesReportNoDuplicates() {
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Row")),
        ResolvedNode(identity: testIdentity("Root", "B"), kind: .view("Row")),
      ]
    )

    let index = RetainedFrameIndex(frame: frame(resolvedTree: root))

    #expect(index.duplicateRuntimeIdentities.isEmpty)
  }

  @Test("retained invalidation uses structural adjacency for present identities")
  func retainedInvalidationUsesStructuralAdjacencyForPresentIdentities() {
    let sibling = ResolvedNode(
      identity: testIdentity("Root", "A"),
      kind: .view("Sibling")
    )
    let pathDescendantButStructuralSibling = ResolvedNode(
      identity: testIdentity("Root", "A", "B"),
      kind: .view("Text")
    )
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [sibling, pathDescendantButStructuralSibling]
    )
    let retainedLayout = RetainedLayoutSession(
      previousFrameIndex: RetainedFrameIndex(frame: frame(resolvedTree: root)),
      invalidatedIdentities: [sibling.identity]
    )

    #expect(retainedLayout.invalidationAffectsSubtree(at: sibling.identity))
    #expect(
      !retainedLayout.invalidationAffectsSubtree(at: pathDescendantButStructuralSibling.identity))
  }

  @Test("retained invalidation still falls back for unindexed synthetic identities")
  func retainedInvalidationFallsBackForSyntheticIdentities() {
    let child = ResolvedNode(
      identity: testIdentity("Root", "Slot[0]", "ID[42]"),
      kind: .view("Text")
    )
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [child]
    )
    let retainedLayout = RetainedLayoutSession(
      previousFrameIndex: RetainedFrameIndex(frame: frame(resolvedTree: root)),
      invalidatedIdentities: [testIdentity("Root", "Slot[0]")]
    )

    #expect(retainedLayout.invalidationAffectsSubtree(at: child.identity))
  }

  @Test("patching initializer is byte-equivalent to a full rebuild")
  func patchingInitializerMatchesFullRebuild() {
    let initial = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Text"))
      ]
    )
    let updated = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Text")),
        ResolvedNode(identity: testIdentity("Root", "B"), kind: .view("Text")),
      ]
    )
    let previous = RetainedFrameIndex(frame: frame(resolvedTree: initial))
    let updatedFrame = frame(resolvedTree: updated)

    let patched = RetainedFrameIndex(patching: previous, with: updatedFrame)
    let rebuilt = RetainedFrameIndex(frame: updatedFrame)

    #expect(patched.isByteEquivalent(to: rebuilt))
  }

  @Test("structural subtree signatures include child structure")
  func structuralSubtreeSignaturesIncludeChildren() throws {
    let initial = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Text"))
      ]
    )
    let updated = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(identity: testIdentity("Root", "A"), kind: .view("Text")),
        ResolvedNode(identity: testIdentity("Root", "B"), kind: .view("Text")),
      ]
    )

    let initialIndex = RetainedFrameIndex(frame: frame(resolvedTree: initial))
    let updatedIndex = RetainedFrameIndex(frame: frame(resolvedTree: updated))
    let initialRootKey = try #require(initialIndex.structuralFrame.root)
    let updatedRootKey = try #require(updatedIndex.structuralFrame.root)

    #expect(
      initialIndex.structuralFrame.subtreeSignatureByNode[initialRootKey]
        != updatedIndex.structuralFrame.subtreeSignatureByNode[updatedRootKey]
    )
  }
}

private func frame(
  resolvedTree: ResolvedNode
) -> FrameArtifacts {
  let measured = measuredTree(from: resolvedTree)
  let placed = placedTree(from: resolvedTree)
  let draw = drawTree(from: resolvedTree)
  return FrameArtifacts(
    resolvedTree: resolvedTree,
    measuredTree: measured,
    placedTree: placed,
    semanticSnapshot: .init(),
    drawTree: draw,
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
    identity: node.identity,
    proposal: .unspecified,
    measuredSize: .zero,
    childMeasurements: node.children.map(measuredTree(from:))
  )
}

private func placedTree(
  from node: ResolvedNode
) -> PlacedNode {
  PlacedNode(
    identity: node.identity,
    kind: node.kind,
    bounds: .init(origin: .zero, size: .zero),
    children: node.children.map(placedTree(from:))
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
