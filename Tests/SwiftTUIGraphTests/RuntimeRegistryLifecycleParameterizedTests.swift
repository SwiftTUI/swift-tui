import Testing

@testable import SwiftTUIGraph

/// Per-kind lifecycle contract for the unified registry family (F109),
/// driven through the publication-oracle fingerprint so every assertion is
/// generic over `RuntimeRegistrationKind`. The kind-totality suite pins that
/// every family is *wired into* the fan-outs; this suite pins what the
/// fan-outs *do* for each family: empty-snapshot restores are no-ops
/// (the F105 family dimension), subtree removal splits child from sibling,
/// reset empties, and the node-liveness prune drops exactly the families that
/// participate in it (the F100/F101 contract, family-wide).
@MainActor
@Suite("Registry lifecycle per kind")
struct RuntimeRegistryLifecycleParameterizedTests {
  private func populatedSet(
    _ kind: RuntimeRegistrationKind,
    identity: Identity
  ) -> RuntimeRegistrationSet {
    let node = RegistrationKindDriver.makeRecordingNode(identity: identity)
    ViewNodeContext.withValue(node) {
      RegistrationKindDriver.record(kind, on: node, identity: identity)
    }
    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: node.registeredHandlers)
    return set
  }

  private func namespaces(_ set: RuntimeRegistrationSet) -> Set<String> {
    RegistrationKindDriver.fingerprintNamespaces(set.publicationOracleFingerprint())
  }

  @Test(
    "restoring an empty snapshot is a no-op for every family",
    arguments: RuntimeRegistrationKind.allCases
  )
  func restoreOfEmptySnapshotIsANoOp(_ kind: RuntimeRegistrationKind) {
    let set = populatedSet(kind, identity: testIdentity("Root", "Leaf"))
    let before = set.publicationOracleFingerprint()
    #expect(!before.isEmpty)

    set.restore(from: NodeHandlers())

    #expect(set.publicationOracleFingerprint() == before)
  }

  @Test(
    "removeSubtrees drops the subtree's registrations and keeps the sibling's",
    arguments: RuntimeRegistrationKind.allCases
  )
  func removeSubtreesSplitsChildFromSibling(_ kind: RuntimeRegistrationKind) {
    let parent = testIdentity("Root", "Parent")
    let child = testIdentity("Root", "Parent", "Child")
    let sibling = testIdentity("Root", "Sibling")

    let nodes = RegistrationKindDriver.makeRecordingNodes(identities: [child, sibling])
    let (childNode, siblingNode) = (nodes[0], nodes[1])
    ViewNodeContext.withValue(childNode) {
      RegistrationKindDriver.record(kind, on: childNode, identity: child)
    }
    ViewNodeContext.withValue(siblingNode) {
      RegistrationKindDriver.record(kind, on: siblingNode, identity: sibling)
    }

    // Two bare `restore(from:)` calls are full-rebuild (replace) semantics
    // for some families; union-compose the two nodes' handlers first via
    // absorbAdopted — the API production uses to merge adopted registrations.
    var combined = NodeHandlers()
    combined.absorbAdopted(childNode.registeredHandlers)
    combined.absorbAdopted(siblingNode.registeredHandlers)
    let set = RuntimeRegistrationSet.scratch()
    set.restore(from: combined)
    let populated = set.publicationOracleFingerprint()
    #expect(!populated.isEmpty)
    #expect(
      populated.keys.contains { $0.contains(child.path) },
      "\(kind): the child's registration must be present before removal for this test to mean anything"
    )

    set.removeSubtrees(rootedAt: [parent])

    let remaining = set.publicationOracleFingerprint()
    #expect(remaining != populated, "removing \(kind)'s subtree changed nothing")
    for key in remaining.keys {
      #expect(
        !key.contains(child.path),
        "\(kind): subtree-owned fingerprint bucket survived removeSubtrees: \(key)"
      )
    }
    #expect(
      remaining.keys.contains { $0.contains(sibling.path) },
      "\(kind): the sibling's registration should survive subtree removal"
    )
  }

  @Test(
    "resetAll empties every family's fingerprint",
    arguments: RuntimeRegistrationKind.allCases
  )
  func resetAllEmptiesTheFingerprint(_ kind: RuntimeRegistrationKind) {
    let set = populatedSet(kind, identity: testIdentity("Root", "Leaf"))
    #expect(!set.publicationOracleFingerprint().isEmpty)

    set.resetAll()

    #expect(set.publicationOracleFingerprint().isEmpty)
  }

  @Test(
    "node-liveness prune drops exactly the participating families' departed state",
    arguments: RuntimeRegistrationKind.allCases
  )
  func pruneContractPerKind(_ kind: RuntimeRegistrationKind) {
    // The gesture registries force-drop unowned state outright. The key
    // handler registry participates too, but only for a bucket whose owner
    // node has provably departed: it buckets stacked handlers per contributing
    // owner, and `removeSubtrees(rootedAt:)` matches on the owner's IDENTITY,
    // which an `.id(_:)`-re-rooted control holds stable while its registering
    // node re-mints — so nothing else could ever reach those buckets and they
    // accumulated one per generation.
    //
    // F101 sequencing was reviewed for that addition and does not bind here:
    // the hazard it protects is the POINTER registry's live captures and hover
    // recency, which the paired-region pass re-keys immediately after this
    // fan-out. Key handlers are stateless dispatch closures with no
    // interaction state to strand, so evicting a departed owner's bucket
    // cannot release a live capture. The pointer registry still deliberately
    // abstains.
    let set = populatedSet(kind, identity: testIdentity("Root", "Leaf"))
    let before = set.publicationOracleFingerprint()
    #expect(!before.isEmpty)

    set.pruneOrphanedGestures(keeping: [])

    let after = set.publicationOracleFingerprint()
    if kind == .gesture || kind == .gestureState || kind == .keyHandler {
      #expect(
        after != before,
        "\(kind): state owned by a departed node must be dropped by prune"
      )
    } else {
      #expect(
        after == before,
        "\(kind): prune must stay a no-op — if this family gained a prune override, review the FocusSync sequencing (F101) and update this contract"
      )
    }
  }
}
