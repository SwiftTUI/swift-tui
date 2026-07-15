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

  @Test("inverted invalidation queries agree with the reference subtree walk")
  func invertedInvalidationQueriesAgreeWithReferenceWalk() {
    // A tree with depth, siblings, a duplicate identity, and multiple
    // branches, exercised against every identity with assorted invalidation
    // sets — including empty, synthetic (absent from the frame), duplicates,
    // and the root. The reference implementations below are the pre-F142
    // walk-based algorithms, kept verbatim as the semantic pin.
    let duplicate = testIdentity("Root", "List", "Row[dup]")
    let root = ResolvedNode(
      identity: testIdentity("Root"),
      kind: .root,
      children: [
        ResolvedNode(
          identity: testIdentity("Root", "List"),
          kind: .view("List"),
          children: [
            ResolvedNode(identity: duplicate, kind: .view("Row")),
            ResolvedNode(identity: duplicate, kind: .view("Row")),
            ResolvedNode(
              identity: testIdentity("Root", "List", "Row[2]"),
              kind: .view("Row"),
              children: [
                ResolvedNode(
                  identity: testIdentity("Root", "List", "Row[2]", "Label"),
                  kind: .view("Text")
                )
              ]
            ),
          ]
        ),
        ResolvedNode(
          identity: testIdentity("Root", "Sidebar"),
          kind: .view("VStack"),
          children: [
            ResolvedNode(
              identity: testIdentity("Root", "Sidebar", "Item"),
              kind: .view("Text")
            )
          ]
        ),
      ]
    )
    let index = StructuralFrameIndex(root: root)
    let allIdentities = Array(index.runtimeIdentities)
    let synthetic = testIdentity("Root", "Sheet", "NotInFrame")

    let invalidationSets: [Set<Identity>] = [
      [],
      [testIdentity("Root")],
      [duplicate],
      [testIdentity("Root", "List", "Row[2]", "Label")],
      [testIdentity("Root", "Sidebar")],
      [synthetic],
      [synthetic, testIdentity("Root", "List")],
      [duplicate, testIdentity("Root", "Sidebar", "Item")],
    ]

    for invalidated in invalidationSets {
      for identity in allIdentities + [synthetic] {
        #expect(
          index.hasInvalidatedAncestor(of: identity, invalidatedIdentities: invalidated)
            == referenceHasInvalidatedAncestor(
              index, of: identity, invalidatedIdentities: invalidated),
          "ancestor query diverged for \(identity) vs \(invalidated)"
        )
        #expect(
          index.containsInvalidatedDescendant(of: identity, invalidatedIdentities: invalidated)
            == referenceContainsInvalidatedDescendant(
              index, of: identity, invalidatedIdentities: invalidated),
          "descendant query diverged for \(identity) vs \(invalidated)"
        )
        #expect(
          index.intersectsSubtree(at: identity, invalidatedIdentities: invalidated)
            == referenceIntersectsSubtree(
              index, at: identity, invalidatedIdentities: invalidated),
          "intersect query diverged for \(identity) vs \(invalidated)"
        )
      }
    }
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

// The pre-F142 walk-based invalidation queries, kept verbatim as the
// reference semantics for the inverted implementations.
private func referenceNodeKeys(
  _ index: StructuralFrameIndex,
  for identities: Set<Identity>
) -> Set<StructuralNodeKey> {
  var keys: Set<StructuralNodeKey> = []
  for identity in identities {
    keys.formUnion(index.nodes(for: identity))
  }
  return keys
}

private func referenceHasInvalidatedAncestor(
  _ index: StructuralFrameIndex,
  of identity: Identity,
  invalidatedIdentities: Set<Identity>
) -> Bool? {
  let keys = index.nodes(for: identity)
  guard !keys.isEmpty else {
    return nil
  }
  let invalidatedNodes = referenceNodeKeys(index, for: invalidatedIdentities)
  for key in keys {
    var parent = index.parentByNode[key]
    while let current = parent {
      if invalidatedNodes.contains(current) {
        return true
      }
      if let parentIdentity = index.runtimeIdentityByNode[current],
        invalidatedIdentities.contains(parentIdentity)
      {
        return true
      }
      parent = index.parentByNode[current]
    }
  }
  return false
}

private func referenceContainsInvalidatedDescendant(
  _ index: StructuralFrameIndex,
  of identity: Identity,
  invalidatedIdentities: Set<Identity>
) -> Bool? {
  let keys = index.nodes(for: identity)
  guard !keys.isEmpty else {
    return nil
  }
  let invalidatedNodes = referenceNodeKeys(index, for: invalidatedIdentities)
  for key in keys {
    guard let range = index.subtreeRangeByNode[key] else {
      continue
    }
    for descendant in index.postorder[range] where descendant != key {
      if invalidatedNodes.contains(descendant) {
        return true
      }
      if let descendantIdentity = index.runtimeIdentityByNode[descendant],
        invalidatedIdentities.contains(descendantIdentity)
      {
        return true
      }
    }
  }
  return false
}

private func referenceIntersectsSubtree(
  _ index: StructuralFrameIndex,
  at identity: Identity,
  invalidatedIdentities: Set<Identity>
) -> Bool? {
  if invalidatedIdentities.contains(identity) {
    return true
  }
  guard !index.nodes(for: identity).isEmpty else {
    return nil
  }
  if referenceContainsInvalidatedDescendant(
    index,
    of: identity,
    invalidatedIdentities: invalidatedIdentities
  ) == true {
    return true
  }
  if referenceHasInvalidatedAncestor(
    index,
    of: identity,
    invalidatedIdentities: invalidatedIdentities
  ) == true {
    return true
  }
  return false
}
