import Testing

@testable import SwiftTUIGraph

/// Direct units for the shared identity-keyed lifecycle store (F102 tier 1).
/// The adopting registries' behavior is pinned family-wide by the per-kind
/// lifecycle suite and the scoped-restore-equals-full-rebuild net; these
/// tests pin the store's own contract — in particular the owner-fallback
/// rules the family repeated inline for years — so a future adopter can
/// rely on them without re-deriving the semantics from a sibling registry.
@MainActor
@Suite("IdentityKeyedRegistryStorage")
struct IdentityKeyedRegistryStorageTests {
  @Test("set is last-write-wins and stamps the owner")
  func setIsLastWriteWins() {
    var store = IdentityKeyedRegistryStorage<String>()
    let identity = testIdentity("Root", "Leaf")

    store.set("first", for: identity, owner: .init(identity: identity))
    store.set("second", for: identity, owner: .init(identity: identity))

    #expect(store[identity] == "second")
    #expect(store.values.count == 1)
    #expect(store.ownersByIdentity[identity]?.identity == identity)
  }

  @Test("reset empties both the value map and the owner companion")
  func resetEmptiesBothMaps() {
    var store = IdentityKeyedRegistryStorage<Int>()
    let identity = testIdentity("Root", "Leaf")
    store.set(1, for: identity, owner: .init(identity: identity))

    store.reset()

    #expect(store.values.isEmpty)
    #expect(store.ownersByIdentity.isEmpty)
  }

  @Test("removeSubtrees drops the subtree's entries and keeps the sibling's")
  func removeSubtreesSplitsChildFromSibling() {
    var store = IdentityKeyedRegistryStorage<Int>()
    let parent = testIdentity("Root", "Parent")
    let child = testIdentity("Root", "Parent", "Child")
    let sibling = testIdentity("Root", "Sibling")
    store.set(1, for: child, owner: .init(identity: child))
    store.set(2, for: sibling, owner: .init(identity: sibling))

    store.removeSubtrees(rootedAt: [parent])

    #expect(store[child] == nil)
    #expect(store.ownersByIdentity[child] == nil)
    #expect(store[sibling] == 2)
  }

  @Test("removeSubtrees derives a fallback owner for entries restored without one")
  func removeSubtreesFallsBackToIdentityDerivedOwner() {
    var store = IdentityKeyedRegistryStorage<Int>()
    let parent = testIdentity("Root", "Parent")
    let child = testIdentity("Root", "Parent", "Child")
    // A snapshot restored with no owner entry leaves the owner map empty
    // for `child`; subtree removal must still match it via the
    // identity-derived fallback.
    store.restore([child: 1])
    #expect(store.ownersByIdentity[child]?.viewNodeID == nil)

    store.removeSubtrees(rootedAt: [parent])

    #expect(store[child] == nil)
  }

  @Test("restore of an empty snapshot is a no-op; a real one overlays per identity")
  func restoreOverlaysPerIdentity() {
    var store = IdentityKeyedRegistryStorage<String>()
    let kept = testIdentity("Root", "Kept")
    let replaced = testIdentity("Root", "Replaced")
    store.set("live-kept", for: kept, owner: .init(identity: kept))
    store.set("live-replaced", for: replaced, owner: .init(identity: replaced))

    store.restore([:])
    #expect(store[kept] == "live-kept")

    let restoredOwner = RuntimeRegistrationOwnerKey(identity: replaced)
    store.restore([replaced: "restored"], ownersByIdentity: [replaced: restoredOwner])

    #expect(store[kept] == "live-kept", "identities absent from the snapshot are untouched")
    #expect(store[replaced] == "restored", "snapshot entries replace live ones per identity")
    #expect(store.ownersByIdentity[replaced] == restoredOwner)
  }
}
